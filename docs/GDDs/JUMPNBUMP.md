# Jump and Bump Game Design Document (GDD)

## Overview
Jump and Bump is a classic side-scrolling multiplayer platformer deathmatch. Players control cute bunnies with the goal of eliminating opponents by jumping on their heads. This port to the FoldBack engine exercises vertical physics, gravity, and pixel-perfect collision detection.

## Core Mechanics

### 1. The Map (Level)
- **Original Layout**: Uses the classic 400x256 pixel arena mapped to a 22x17 tile grid.
- **Tile Types**:
    - `0`: Void/Empty (Air).
    - `1`: Solid (Ground/Walls).
    - `2`: Water (Buoyant area).
    - `3`: Ice (Low friction).
- **Coordinate System**: Fixed-point math with a 1000x scale (1000 units = 1 pixel).

### 2. Physics & Movement
- **Gravity**: Constant downward acceleration applied every tick.
- **Horizontal Inertia**: Movement features acceleration and damping (friction).
- **Jumping**: Impulse-based vertical force applied when the player is on solid ground or ice.
- **Screen Wrapping**: Players that move beyond the left or right boundaries wrap around to the opposite side of the screen.

### 3. Combat (The "Squish")
- **Mechanism**: A player eliminates an opponent by landing on their head from above while falling.
- **Lethality**:
    - Jumping player must have a positive vertical velocity (falling).
    - Jumping player's bounding box must overlap with the target's bounding box.
    - Jumping player must be vertically above the target.
- **Result**:
    - Target bunny is "squished" (Health set to 0).
    - Attacking bunny receives a vertical bounce impulse (same as a jump).

### 4. Respawn System
- **Deterministic Spawning**: When a player dies, they respawn at a random location selected by a shared LCG (Linear Congruential Generator) seed.
- **Valid Spawn Points**: The algorithm searches for empty tiles (`0`) directly above solid (`1`) or ice (`3`) tiles to ensure players don't spawn in the air or inside walls.

## Visuals
- **Pixel Art**: Rendered in a 400x256 resolution using nearest-neighbor scaling (`image-rendering: pixelated`).
- **Assets**: 
    - `gateway/jumpnbump/gfx/bg.gif`: The iconic original background.
    - `gateway/jumpnbump/gfx/rabbit.gif`: Sprite sheet containing bunny animations.

## Technical Implementation
- **Lisp (Server)**:
    - `src/games/jumpnbump.lisp`: Pure functional simulation including gravity, collision, and squish logic.
- **JavaScript (Client)**:
    - `gateway/jumpnbump/logic.js`: Mirrored logic for zero-latency Client-Side Prediction (CSP).
- **Determinism**: 
    - All physics calculations use fixed-point arithmetic to prevent floating-point drift between Lisp (SBCL) and JavaScript (V8).
    - Shared PRNG seed ensures spawn positions are identical on all clients.
- **Synchronization**: Authoritative server with high-frequency state broadcasts and client-side reconciliation.
