# Sumo Game Design Document (GDD)

## Overview
Sumo is a physics-based multiplayer game where players control circular avatars in a circular ring. The goal is to remain within the ring while attempting to push other players out.

## Core Mechanics

### 1. The Ring (Arena)
- **Shape**: Circle centered at (0, 0).
- **Radius**: `10.0` units (+ring-radius+).
- **Out of Bounds**: If a player's center moves beyond the ring's radius, they are eliminated.

### 2. Players
- **Shape**: Circle.
- **Radius**: `0.5` units (+player-radius+).
- **Health (h)**: 
    - `100`: Active and inside the ring.
    - `0`: Eliminated (out of bounds).
- **State**: Each player has position `(x, y)`, velocity `(vx, vy)`, and health `h`.

### 3. Movement & Physics
- **Acceleration**: Players apply acceleration based on directional input (`dx`, `dy`).
    - `+acceleration+ = 0.015`.
- **Friction**: Velocity is multiplied by a friction coefficient every tick.
    - `+friction+ = 0.96`.
- **Update Loop**:
    1. `new_vx = (old_vx * friction) + (input_dx * acceleration)`
    2. `new_vy = (old_vy * friction) + (input_dy * acceleration)`
    3. `new_x = old_x + new_vx`
    4. `new_y = old_y + new_vy`

### 4. Collisions & Interactions
- **Detection**: Two players collide if the distance between their centers is less than `2 * +player-radius+` (1.0 units).
- **Interaction (Push)**: When two players collide, a "push" force is applied to their velocities.
- **Deterministic Push Force**:
    - `+push-force+ = 0.05`.
    - To maintain cross-platform determinism, the push direction is based on the sign of the relative distance rather than normalized vectors.
    - If `p2.x > p1.x`, `p1` receives `-push-force` to its `vx`.
    - If `p2.y > p1.y`, `p1` receives `-push-force` to its `vy`.

## Technical Implementation
- **Lisp (Server)**: `src/sumo.lisp`
- **JavaScript (Client)**: `gateway/sumo-logic.js`
- **Synchronization**: The game uses a tick-based state synchronization. The server sends authoritative state deltas to clients.
- **Cross-Platform**: Logic is mirrored between Lisp and JS to allow for client-side prediction and server-side validation.
