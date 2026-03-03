# FoldBack: Engineering Sample

**FoldBack** is a high-performance, authoritative game server engine written in **Common Lisp**. It treats the entire game world as a single, immutable value using **Persistent Data Structures (FSet)**.

## 🏗 System Architecture

The engine is split into three main layers:

1.  **Functional Core (Lisp):** The pure simulation logic. `(update-game state inputs)` returns a new state. No side effects.
2.  **Authoritative Server (Lisp):** A high-frequency UDP server (60Hz) that manages world history, input buffering, and delta-encoded broadcasts.
3.  **Connectivity Gateway (Go):** A protocol-agnostic proxy that handles WebSockets and WebRTC, forwarding traffic to the Lisp core via local UDP.

## 🕹 Game Features

-   **Massive Multiplayer:** Support for 50+ concurrent players with low-latency updates.
-   **Destructible Environment:** Randomly generated maps with hard walls and destructible crates.
-   **Advanced Bomb Mechanics:** 
    *   **Chain Reactions:** Bombs can trigger other bombs.
    *   **Passable-Until-Left:** Players can step out of bombs they've just planted without getting stuck.
    *   **Visual Fire Areas:** Real-time tracking and rendering of explosion rays.
-   **AI Sentry Bots:** Patrolling bots that move randomly and kill players on contact. Bots can also be destroyed by bombs.
-   **Smart Respawn System:** 5-second respawn timer with a spawn algorithm that ensures players never spawn stuck or on top of another living player.

## 📡 Networking Protocols

The Go gateway serves the frontend and provides two connection methods:

1.  **WebSockets (Default):** 
    *   Fastest connection time.
    *   Highly compatible with standard web infrastructure.
    *   Accessed via `http://localhost:8080`
2.  **WebRTC (DataChannels):** 
    *   UDP-based peer-to-peer style communication.
    *   Lower overhead for high-frequency input.
    *   Accessed via `http://localhost:8080?protocol=webrtc`

## 🛠 Developer Tooling

-   **Autoplay Mode:** Test server load and bot behavior by appending `?autoplay=1` to the URL.
-   **Automated Testing:** Full end-to-end multiplayer verification using **Playwright**.
-   **Granular Unit Tests:** Isolated Lisp tests for physics, rounding, and game rules.

---

*“In FoldBack, time is just a variable you can reduce over.”*
