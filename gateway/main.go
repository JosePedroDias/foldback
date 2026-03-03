package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"

	"github.com/google/uuid"
	"github.com/pion/webrtc/v3"
)

const (
	LispServerAddr = "127.0.0.1:4444"
	SignalingPort  = ":8080"
)

type Client struct {
	ID         string
	UDPConn    *net.UDPConn
	RTCData    *webrtc.DataChannel
}

var (
	clients = make(map[string]*Client)
	mu      sync.Mutex
)

func main() {
	// 1. Signaling Server
	http.HandleFunc("/offer", handleOffer)
	http.Handle("/", http.FileServer(http.Dir(".")))
	fmt.Printf("FoldBack Gateway started at %s (Signaling and Frontend)\n", SignalingPort)
	log.Fatal(http.ListenAndServe(SignalingPort, nil))
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
		fmt.Printf("New DataChannel for client %s\n", clientID)

		udpAddr, _ := net.ResolveUDPAddr("udp", LispServerAddr)
		udpConn, _ := net.DialUDP("udp", nil, udpAddr)

		client := &Client{ID: clientID, UDPConn: udpConn, RTCData: d}
		mu.Lock()
		clients[clientID] = client
		mu.Unlock()

		d.OnClose(func() {
			fmt.Printf("DataChannel closed for client %s\n", clientID)
			mu.Lock()
			delete(clients, clientID)
			mu.Unlock()
			udpConn.Close()
		})

		d.OnMessage(func(msg webrtc.DataChannelMessage) {
			udpConn.Write(msg.Data)
		})

		// UDP -> WebRTC
		go func() {
			rawBuf := make([]byte, 8192) // Increased buffer for large map updates
			for {
				n, err := udpConn.Read(rawBuf)
				if err != nil {
					return
				}
				if d.ReadyState() == webrtc.DataChannelStateOpen {
					// IMPORTANT: Send as Text for index.html JSON.parse
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
