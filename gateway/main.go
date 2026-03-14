package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/pion/turn/v2"
	"github.com/pion/webrtc/v3"
)

const (
	DefaultLispAddr = "127.0.0.1:4444"
	SignalingPort    = ":8080"
	STUNPort         = 3478
	SpawnBasePort    = 4445
)

// GameDef defines how to spawn a Lisp game server.
// SBCLEval is a format string with %d for the port.
type GameDef struct {
	Eval string
}

// Registry of all known games and their sbcl start-server eval strings.
// Port is injected via fmt.Sprintf at spawn time.
var gameRegistry = map[string]GameDef{
	"airhockey": {
		Eval: `(foldback:start-server :port %d :game-id "airhockey" :simulation-fn #'foldback:airhockey-update :serialization-fn #'foldback:airhockey-serialize :join-fn #'foldback:airhockey-join)`,
	},
	"bomberman": {
		Eval: `(let* ((level (foldback:make-bomberman-map)) (bots (foldback:spawn-bots level 3))) (foldback:start-server :port %d :game-id "bomberman" :simulation-fn #'foldback:bomberman-update :serialization-fn #'foldback:bomberman-serialize :join-fn #'foldback:bomberman-join :initial-custom-state (fset:map (:level level) (:bots bots) (:seed 123))))`,
	},
	"gofish": {
		Eval: `(foldback:start-server :port %d :game-id "gofish" :simulation-fn #'foldback:gf-update :serialization-fn #'foldback:gf-serialize :join-fn #'foldback:gf-join :tick-rate 10 :initial-custom-state (fset:map (:seed 12345)))`,
	},
	"jumpnbump": {
		Eval: `(foldback:start-server :port %d :game-id "jumpnbump" :simulation-fn #'foldback:jnb-update :serialization-fn #'foldback:jnb-serialize :join-fn #'foldback:jnb-join :initial-custom-state (fset:map (:seed 123)))`,
	},
	"pong": {
		Eval: `(foldback:start-server :port %d :game-id "pong" :simulation-fn #'foldback:pong-update :serialization-fn #'foldback:pong-serialize :join-fn #'foldback:pong-join)`,
	},
	"tictactoe": {
		Eval: `(foldback:start-server :port %d :game-id "tictactoe" :simulation-fn #'foldback:ttt-update :serialization-fn #'foldback:ttt-serialize :join-fn #'foldback:ttt-join :tick-rate 10)`,
	},
}

type SpawnedGame struct {
	Port      int
	Cmd       *exec.Cmd
	Ready     chan struct{} // closed when the game server is ready
	StartedAt time.Time
}

var (
	spawnMode    bool
	spawnedGames = make(map[string]*SpawnedGame)
	spawnMu      sync.Mutex
	nextPort     = SpawnBasePort

	// Per-game client count (works in both spawn and non-spawn mode)
	clientCount   = make(map[string]int)
	clientCountMu sync.Mutex
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func startSTUN() {
	udpListener, err := net.ListenPacket("udp4", fmt.Sprintf("0.0.0.0:%d", STUNPort))
	if err != nil {
		log.Printf("STUN server failed to start: %v", err)
		return
	}

	_, err = turn.NewServer(turn.ServerConfig{
		Realm: "localhost",
		AuthHandler: func(username string, realm string, srcAddr net.Addr) ([]byte, bool) {
			return nil, false // STUN-only, no TURN auth needed
		},
		PacketConnConfigs: []turn.PacketConnConfig{{
			PacketConn: udpListener,
			RelayAddressGenerator: &turn.RelayAddressGeneratorStatic{
				RelayAddress: net.ParseIP("127.0.0.1"),
				Address:      "0.0.0.0",
			},
		}},
	})
	if err != nil {
		log.Printf("STUN server error: %v", err)
		return
	}

	fmt.Printf("STUN server started on :%d\n", STUNPort)
}

// resolveAddr returns the UDP address for a game.
// In spawn mode, it spawns the game on demand if needed.
// Without spawn mode, all games route to DefaultLispAddr.
func resolveAddr(game string) (string, error) {
	if !spawnMode {
		return DefaultLispAddr, nil
	}
	if game == "" {
		return "", fmt.Errorf("spawn mode requires a game name in the URL path")
	}
	sg, err := ensureSpawned(game)
	if err != nil {
		return "", err
	}
	// Wait for the game to be ready
	<-sg.Ready
	return fmt.Sprintf("127.0.0.1:%d", sg.Port), nil
}

// ensureSpawned starts a game server if it isn't already running.
func ensureSpawned(game string) (*SpawnedGame, error) {
	spawnMu.Lock()
	defer spawnMu.Unlock()

	if sg, ok := spawnedGames[game]; ok {
		return sg, nil
	}

	def, ok := gameRegistry[game]
	if !ok {
		return nil, fmt.Errorf("unknown game: %s", game)
	}

	port := nextPort
	nextPort++

	eval := fmt.Sprintf(def.Eval, port)

	// Run sbcl from the project root (parent of gateway/)
	projectRoot := ".."
	cmd := exec.Command("sbcl",
		"--load", "foldback.asd",
		"--eval", "(ql:quickload :foldback)",
		"--eval", eval,
	)
	cmd.Dir = projectRoot

	ready := make(chan struct{})
	sg := &SpawnedGame{Port: port, Cmd: cmd, Ready: ready, StartedAt: time.Now()}
	spawnedGames[game] = sg

	// Capture stdout to detect readiness
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		delete(spawnedGames, game)
		return nil, fmt.Errorf("failed to capture stdout for %s: %w", game, err)
	}
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		delete(spawnedGames, game)
		return nil, fmt.Errorf("failed to start %s: %w", game, err)
	}

	fmt.Printf("Spawning %s on port %d (pid %d)\n", game, port, cmd.Process.Pid)

	// Watch stdout for the ready message
	go func() {
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			line := scanner.Text()
			fmt.Printf("[%s] %s\n", game, line)
			if strings.Contains(line, "FoldBack Engine Started") {
				close(ready)
			}
		}
	}()

	// Monitor process exit
	go func() {
		err := cmd.Wait()
		spawnMu.Lock()
		delete(spawnedGames, game)
		spawnMu.Unlock()
		if err != nil {
			fmt.Printf("Game %s exited with error: %v\n", game, err)
		} else {
			fmt.Printf("Game %s exited\n", game)
		}
	}()

	return sg, nil
}

// shutdownAll kills all spawned game processes.
func shutdownAll() {
	spawnMu.Lock()
	defer spawnMu.Unlock()
	for name, sg := range spawnedGames {
		fmt.Printf("Stopping %s (pid %d)\n", name, sg.Cmd.Process.Pid)
		sg.Cmd.Process.Signal(syscall.SIGTERM)
	}
}

func clientConnect(game string) {
	if game == "" {
		return
	}
	clientCountMu.Lock()
	clientCount[game]++
	fmt.Printf("Game %s: %d player(s) connected\n", game, clientCount[game])
	clientCountMu.Unlock()
}

func clientDisconnect(game string) {
	if game == "" {
		return
	}
	clientCountMu.Lock()
	clientCount[game]--
	remaining := clientCount[game]
	if remaining <= 0 {
		delete(clientCount, game)
		remaining = 0
	}
	fmt.Printf("Game %s: %d player(s) connected\n", game, remaining)
	clientCountMu.Unlock()

	if remaining == 0 && spawnMode {
		stopGame(game)
	}
}

// stopGame kills a spawned game server and removes it from the map.
func stopGame(game string) {
	spawnMu.Lock()
	sg, ok := spawnedGames[game]
	if !ok {
		spawnMu.Unlock()
		return
	}
	delete(spawnedGames, game)
	spawnMu.Unlock()

	fmt.Printf("All players left %s — stopping server (pid %d)\n", game, sg.Cmd.Process.Pid)
	sg.Cmd.Process.Signal(syscall.SIGTERM)
}

func main() {
	flag.BoolVar(&spawnMode, "spawn", false, "Auto-spawn Lisp game servers on demand")
	flag.Parse()

	if spawnMode {
		fmt.Println("Spawn mode enabled — game servers will be started on demand")
		fmt.Printf("Available games: %s\n", strings.Join(gameNames(), ", "))
	}

	// Clean up spawned processes on exit
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		fmt.Println("\nShutting down...")
		shutdownAll()
		os.Exit(0)
	}()

	// 1. Local STUN server for WebRTC
	startSTUN()

	// 2. Endpoints
	// Game-specific paths (preferred)
	http.HandleFunc("/ws/{game}", handleWS)
	http.HandleFunc("/offer/{game}", handleOffer)
	// Legacy paths (no game in URL — routes to DefaultLispAddr)
	http.HandleFunc("/ws", handleWS)
	http.HandleFunc("/offer", handleOffer)
	// Game list & health API
	http.HandleFunc("/games", handleGames)
	http.HandleFunc("/health", handleHealth)
	http.Handle("/", http.FileServer(http.Dir(".")))

	fmt.Printf("FoldBack Gateway started at %s (Signaling, WS, and Frontend)\n", SignalingPort)
	log.Fatal(http.ListenAndServe(SignalingPort, nil))
}

func gameNames() []string {
	names := make([]string, 0, len(gameRegistry))
	for name := range gameRegistry {
		names = append(names, name)
	}
	return names
}

func handleGames(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	type gameInfo struct {
		Name    string `json:"name"`
		Running bool   `json:"running"`
		Port    int    `json:"port,omitempty"`
	}

	spawnMu.Lock()
	games := make([]gameInfo, 0, len(gameRegistry))
	for name := range gameRegistry {
		info := gameInfo{Name: name}
		if sg, ok := spawnedGames[name]; ok {
			info.Running = true
			info.Port = sg.Port
		}
		games = append(games, info)
	}
	spawnMu.Unlock()

	json.NewEncoder(w).Encode(games)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	type gameHealth struct {
		Name      string     `json:"name"`
		Running   bool       `json:"running"`
		Port      int        `json:"port,omitempty"`
		StartedAt *time.Time `json:"started_at,omitempty"`
		Players   int        `json:"players"`
	}

	spawnMu.Lock()
	clientCountMu.Lock()

	games := make([]gameHealth, 0, len(gameRegistry))
	for name := range gameRegistry {
		info := gameHealth{Name: name, Players: clientCount[name]}
		if sg, ok := spawnedGames[name]; ok {
			info.Running = true
			info.Port = sg.Port
			info.StartedAt = &sg.StartedAt
		}
		games = append(games, info)
	}

	clientCountMu.Unlock()
	spawnMu.Unlock()

	json.NewEncoder(w).Encode(games)
}

func handleWS(w http.ResponseWriter, r *http.Request) {
	game := r.PathValue("game")

	addr, err := resolveAddr(game)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WS Upgrade Error: %v", err)
		return
	}

	clientID := uuid.New().String()
	fmt.Printf("New WS Client: %s -> %s\n", clientID, addr)
	clientConnect(game)

	udpAddr, _ := net.ResolveUDPAddr("udp", addr)
	udpConn, _ := net.DialUDP("udp", nil, udpAddr)

	// Ensure we notify Lisp server on leave
	defer func() {
		fmt.Printf("WS Client Left: %s\n", clientID)
		udpConn.Write([]byte(`{"TYPE":"LEAVE"}`))
		udpConn.Close()
		conn.Close()
		clientDisconnect(game)
	}()

	// WS -> UDP
	go func() {
		for {
			_, message, err := conn.ReadMessage()
			if err != nil {
				return
			}
			udpConn.Write(message)
		}
	}()

	// UDP -> WS
	rawBuf := make([]byte, 8192)
	for {
		n, err := udpConn.Read(rawBuf)
		if err != nil {
			break
		}
		if err := conn.WriteMessage(websocket.TextMessage, rawBuf[:n]); err != nil {
			break
		}
	}
}

func handleOffer(w http.ResponseWriter, r *http.Request) {
	game := r.PathValue("game")

	addr, err := resolveAddr(game)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	var offer webrtc.SessionDescription
	if err := json.NewDecoder(r.Body).Decode(&offer); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	peerConnection, err := webrtc.NewPeerConnection(webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{{URLs: []string{fmt.Sprintf("stun:127.0.0.1:%d", STUNPort)}}},
	})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	clientID := uuid.New().String()

	var udpConn *net.UDPConn
	var udpOnce sync.Once

	cleanupUDP := func() {
		udpOnce.Do(func() {
			if udpConn != nil {
				fmt.Printf("WebRTC Client Left: %s\n", clientID)
				udpConn.Write([]byte(`{"TYPE":"LEAVE"}`))
				udpConn.Close()
				clientDisconnect(game)
			}
			peerConnection.Close()
		})
	}

	peerConnection.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		fmt.Printf("WebRTC %s state: %s\n", clientID, state.String())
		if state == webrtc.PeerConnectionStateFailed || state == webrtc.PeerConnectionStateClosed {
			cleanupUDP()
		}
	})

	peerConnection.OnDataChannel(func(d *webrtc.DataChannel) {
		fmt.Printf("New WebRTC DataChannel: %s\n", clientID)
		clientConnect(game)

		udpAddr, _ := net.ResolveUDPAddr("udp", addr)
		udpConn, _ = net.DialUDP("udp", nil, udpAddr)

		d.OnClose(func() {
			cleanupUDP()
		})

		d.OnMessage(func(msg webrtc.DataChannelMessage) {
			udpConn.Write(msg.Data)
		})

		// UDP -> WebRTC
		go func() {
			rawBuf := make([]byte, 8192)
			for {
				n, err := udpConn.Read(rawBuf)
				if err != nil {
					return
				}
				if d.ReadyState() == webrtc.DataChannelStateOpen {
					d.SendText(string(rawBuf[:n]))
				}
			}
		}()
	})

	if err := peerConnection.SetRemoteDescription(offer); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	answer, _ := peerConnection.CreateAnswer(nil)
	gatherComplete := webrtc.GatheringCompletePromise(peerConnection)
	peerConnection.SetLocalDescription(answer)
	select {
	case <-gatherComplete:
	case <-time.After(2 * time.Second):
	}

	json.NewEncoder(w).Encode(peerConnection.LocalDescription())
}
