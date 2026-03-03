# 💣 Sample Game: Bomberman

This sample demonstrates a **Massive Multiplayer Bomberman** game using an authoritative Lisp server and a WebRTC-to-UDP Go gateway.

## 🏗️ Architecture
1.  **Lisp Server (`src/`):** The authoritative engine. It manages player state, bomb explosions, and map collisions using immutable data structures.
2.  **Go Gateway (`gateway/`):** A signaling server and WebRTC bridge. It converts browser DataChannel messages into UDP packets for the Lisp server.
3.  **Browser Client (`gateway/index.html`):** A simple Canvas-based frontend that renders the game state and sends player inputs.

## 📋 Prerequisites
- **Common Lisp:** [SBCL](http://www.sbcl.org/) (installed and in your PATH).
- **Quicklisp:** [Quicklisp](https://www.quicklisp.org/beta/) (installed in your Lisp environment).
- **Go:** [Go 1.20+](https://go.dev/) (installed and in your PATH).

## 🚀 Setup & Execution

### 1. Install Dependencies
Run the following command to download Lisp libraries (`fset`, `usocket`) and Go modules:
```bash
make setup
```

### 2. Start the Lisp Game Server
In your first terminal, start the authoritative backend:
```bash
make lisp
```
*The server will listen for UDP packets on port `4444`.*

### 3. Start the WebRTC Gateway
In your second terminal, start the gateway and frontend server:
```bash
make gateway
```
*The gateway will start a signaling server and file server on [http://localhost:8080](http://localhost:8080).*

### 4. Play the Game
1.  Open [http://localhost:8080](http://localhost:8080) in your browser.
2.  Open a **second tab or window** at the same address to test multiplayer.
3.  **Controls:**
    - **W/A/S/D:** Move your player.
    - **Space:** Drop a bomb.

## 🛠️ Troubleshooting
- **Lisp Errors:** Ensure `quicklisp` is correctly loaded in your `~/.sbclrc`.
- **Connection Issues:** Verify that port `4444` (UDP) and `8080` (TCP) are not blocked by a firewall.
- **Browser Compatibility:** Use a modern browser (Chrome, Firefox, or Edge) that supports WebRTC DataChannels.
