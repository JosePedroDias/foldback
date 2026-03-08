# Bomberman Game Design Document (GDD)

## Overview
Bomberman is a grid-based multiplayer action game. Players navigate a maze, place bombs to destroy obstacles (crates) and eliminate opponents (players and bots).

## Core Mechanics

### 1. The Map (Level)
- **Grid-Based**: The world is a 2D grid of tiles.
- **Tile Types**:
    - `0`: Empty (Walkable).
    - `1`: Hard Wall (Indestructible, Blocks movement and explosions).
    - `2`: Soft Block / Crate (Destructible by explosions, Blocks movement).
- **Generation**: Typically includes a perimeter of hard walls, a grid of internal hard walls, and randomly placed soft blocks (crates).

### 2. Players
- **Size**: `0.7` units (+player-size+).
- **Health**: 
    - `100`: Alive.
    - `0`: Dead (Eliminated by explosions or bots).
- **Respawn**: Players respawn after a timeout (`5 seconds` or `300 ticks`) at a random valid spawn point.
- **Movement**: 8-way movement with "move-and-slide" collision resolution against walls, bombs, and other players.

### 3. Bombs
- **Placement**: Players can drop a bomb at their current grid-aligned position.
- **Timer**: Bombs explode after `3 seconds` (180 ticks).
- **Radius**: Explosions extend `3 tiles` in cardinal directions (Up, Down, Left, Right).
- **Explosion Rays**:
    - Blocked by Hard Walls.
    - Destroy Soft Blocks (ray stops at the destroyed block).
    - Trigger other bombs (Chain Reaction).
    - Kill players and bots.
- **Collision**: Bombs are solid objects. However, a player who just dropped a bomb can walk "through" it until they exit its bounding box to prevent getting stuck.

### 4. Bots
- **Movement**: Simple AI that moves in a straight line until it hits an obstacle, then picks a random new cardinal direction.
- **Interaction**: Touching a bot instantly kills a player (sets health to 0).
- **Vulnerability**: Bots can be destroyed by bomb explosions.

### 5. Explosions
- **Duration**: Explosion tiles remain visible and lethal for `0.5 seconds` (30 ticks).
- **Lethality**: Any player or bot occupying a tile with an active explosion has their health set to 0.

## Technical Implementation
- **Lisp (Server)**: 
    - `src/games/bomberman.lisp`: Contains all game logic (main loop, map generation, bomb logic, and bot AI).
- **JavaScript (Client)**: `gateway/bomberman/logic.js` (mirrored logic for prediction).
- **Synchronization**: Authoritative server with client-side prediction and reconciliation.
- **Determinism**: Uses a shared seed and deterministic PRNG for synchronized bot movement and map features.
