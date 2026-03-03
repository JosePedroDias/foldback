package main

import (
	"net"
	"testing"
	"time"
)

func TestUDPForwarding(t *testing.T) {
	// 1. Start a mock Lisp Server on a random UDP port
	lispAddr, err := net.ResolveUDPAddr("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	lispConn, err := net.ListenUDP("udp", lispAddr)
	if err != nil {
		t.Fatal(err)
	}
	defer lispConn.Close()
	actualLispAddr := lispConn.LocalAddr().String()

	// 2. Simulate the Gateway's internal client setup
	targetAddr, _ := net.ResolveUDPAddr("udp", actualLispAddr)
	clientUDP, err := net.DialUDP("udp", nil, targetAddr)
	if err != nil {
		t.Fatal(err)
	}
	defer clientUDP.Close()

	// 3. Test sending from Client -> Lisp
	testMsg := []byte("hello lisp")
	go func() {
		clientUDP.Write(testMsg)
	}()

	buf := make([]byte, 1024)
	lispConn.SetReadDeadline(time.Now().Add(time.Second))
	n, remoteAddr, err := lispConn.ReadFromUDP(buf)
	if err != nil {
		t.Fatalf("Lisp server didn't receive message: %v", err)
	}
	if string(buf[:n]) != string(testMsg) {
		t.Errorf("Expected %s, got %s", string(testMsg), string(buf[:n]))
	}

	// 4. Test sending from Lisp -> Client
	responseMsg := []byte("hello client")
	_, err = lispConn.WriteToUDP(responseMsg, remoteAddr)
	if err != nil {
		t.Fatal(err)
	}

	clientBuf := make([]byte, 1024)
	clientUDP.SetReadDeadline(time.Now().Add(time.Second))
	n, err = clientUDP.Read(clientBuf)
	if err != nil {
		t.Fatalf("Client didn't receive response: %v", err)
	}
	if string(clientBuf[:n]) != string(responseMsg) {
		t.Errorf("Expected %s, got %s", string(responseMsg), string(clientBuf[:n]))
	}
}
