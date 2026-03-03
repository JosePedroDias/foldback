package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/pion/webrtc/v3"
)

const (
	LispServerAddr = "127.0.0.1:4444"
	SignalingPort  = ":8080"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type Client struct {
	ID      string
	UDPConn *net.UDPConn
}

var (
	clients = make(map[string]*Client)
	mu      sync.Mutex
)

func main() {
	// 1. Endpoints
	http.HandleFunc("/offer", handleOffer)
	http.HandleFunc("/ws", handleWS)
	http.Handle("/", http.FileServer(http.Dir(".")))

	fmt.Printf("FoldBack Gateway started at %s (Signaling, WS, and Frontend)\n", SignalingPort)
	log.Fatal(http.ListenAndServe(SignalingPort, nil))
}

func handleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WS Upgrade Error: %v", err)
		return
	}
	
	clientID := uuid.New().String()
	fmt.Printf("New WS Client: %s\n", clientID)

	udpAddr, _ := net.ResolveUDPAddr("udp", LispServerAddr)
	udpConn, _ := net.DialUDP("udp", nil, udpAddr)
	
	// Ensure we notify Lisp server on leave
	defer func() {
		fmt.Printf("WS Client Left: %s\n", clientID)
		udpConn.Write([]byte("(:leave t)"))
		udpConn.Close()
		conn.Close()
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
	var offer webrtc.SessionDescription
	if err := json.NewDecoder(r.Body).Decode(&offer); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	peerConnection, err := webrtc.NewPeerConnection(webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{{URLs: []string{"stun:stun.l.google.com:19302"}}},
	})
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	clientID := uuid.New().String()

	peerConnection.OnDataChannel(func(d *webrtc.DataChannel) {
		fmt.Printf("New WebRTC DataChannel: %s\n", clientID)

		udpAddr, _ := net.ResolveUDPAddr("udp", LispServerAddr)
		udpConn, _ := net.DialUDP("udp", nil, udpAddr)

		d.OnClose(func() {
			fmt.Printf("WebRTC DataChannel closed: %s\n", clientID)
			udpConn.Write([]byte("(:leave t)"))
			udpConn.Close()
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
	<-gatherComplete

	json.NewEncoder(w).Encode(peerConnection.LocalDescription())
}
