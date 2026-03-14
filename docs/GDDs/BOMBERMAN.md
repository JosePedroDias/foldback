# Bomberman Game Design Document

## Overview

Bomberman is a grid-based multiplayer action game. Players navigate a 13x11 tile map, placing bombs to destroy crates, eliminate bots, and kill other players. Players respawn after death. There is no win condition -- it is an ongoing deathmatch.

## Core Mechanics

### Map
- **Size**: 13 wide x 11 tall
- **Tile types**: 0 = empty, 1 = hard wall (indestructible), 2 = crate (destructible)
- **Layout**: hard walls form a perimeter and a grid pattern at odd x/y positions; crates are randomly placed on empty tiles with a 30% probability
- **Crates**: destroyed by explosions, becoming empty tiles

### Player
- **Size**: 700 FP (0.7 units), half-size 350 FP
- **Movement**: 100 FP per tick per input axis, with move-and-slide collision resolution
- **Health**: 100 (alive) or 0 (dead)
- **Respawn**: 300 ticks (5 seconds at 60Hz) after death, at a random empty tile with at least 2 clear neighbors and no player overlap

### Bombs
- **Placement**: snaps to the grid tile the player is standing on
- **Timer**: 180 ticks (3 seconds at 60Hz)
- **Explosion range**: 3 tiles in each cardinal direction
- **Explosion behavior**: rays extend outward from bomb tile; blocked by hard walls and crates. Crates are destroyed but stop the ray. Hard walls stop the ray without being destroyed.
- **Explosion duration**: 30 ticks (tracked in explosions map)
- **Kill radius**: 800 FP from explosion tile center (checked as AABB per-axis)
- **Duplicate prevention**: bombs are keyed by grid position ("x,y"); only one bomb per tile

### Bots
- **Speed**: 25 FP per tick (0.025 units)
- **Movement**: move in a straight line; on wall collision, pick a random cardinal direction (using seeded PRNG)
- **Kill radius**: 600 FP (AABB per-axis) -- bots kill players on contact
- **Vulnerability**: bots are killed by explosions (same 800 FP check)

### Bomb Walk-Through
Players can stand on a bomb they placed (they were overlapping when it was created). The "allowed bomb IDs" are computed from the player's current AABB corners. Once the player moves off the bomb tile, they can no longer walk through it.

## Constants (Fixed-Point, scale 1000)

| Constant | Value | Meaning |
|---|---|---|
| PLAYER_SIZE | 700 | Player bounding box (0.7 units) |
| HALF_SIZE | 350 | Half of player size |
| RESPAWN_TIMEOUT | 300 | Ticks until respawn (5 seconds) |
| BOMB_RANGE | 3 | Explosion range in tiles |
| BOMB_TIMER | 180 | Bomb fuse in ticks (3 seconds) |
| EXPLOSION_DURATION | 30 | Explosion visual/kill duration in ticks |
| BOT_SPEED | 25 | Bot movement per tick (0.025 units) |
| EXPLOSION_KILL_RADIUS | 800 | Kill distance from explosion tile center |
| BOT_KILL_RADIUS | 600 | Kill distance from bot center |

## State Shape

```
{
  tick,
  players: {
    id: { x, y, health, death-tick }
  },
  custom-state: {
    level,                        // 2D grid of tile values
    bombs: { "x,y": { x, y, tm } },   // grid coords, timer
    explosions: { "x,y": duration },   // grid coords, remaining ticks
    bots: { id: { x, y, dx, dy } },   // FP coords, FP velocity
    seed                          // PRNG seed for determinism
  }
}
```

## Controls

**Input format**: `{"DX": -1|0|1, "DY": -1|0|1, "DROP_BOMB": true|false, "TICK": <tick>}`

- `dx`, `dy`: movement direction (multiplied by 100 FP internally)
- `drop-bomb`: when truthy, place a bomb at the player's current grid tile

## Physics

### Movement (Move-and-Slide)
1. Try moving on x-axis only: if no collision at (x+dx, y), accept new x
2. Try moving on y-axis only: if no collision at (final_x, y+dy), accept new y
3. Collision checks test all 4 AABB corners against: non-empty tiles, bombs (unless allowed), and other living players

### Tile Lookup
Fixed-point positions are converted to grid indices by: `floor(fpToFloat(fpAdd(pos, 500)))`. The +500 offset (0.5 units) centers the lookup.

### Update Order
Each tick:
1. Player movement (move-and-slide)
2. Bomb placement, timer countdown, explosion generation, crate destruction
3. Explosion kill checks (players and bots)
4. Bot movement and bot-player kill checks
5. Respawn checks (dead players past timeout)

## Implementation Files

- **Lisp server**: `src/games/bomberman.lisp`
- **JS client logic**: `gateway/bomberman/logic.js`
- **JS client entry**: `gateway/bomberman/index.js`

## Key Implementation Notes

- The map uses `fset:map` for immutable persistent data structures. The level is a map of row-index -> (map of col-index -> tile-value).
- Bomb IDs and explosion keys use the string format `"x,y"` with integer grid coordinates.
- The seeded PRNG (`fb-rand-int`) is used for bot direction changes to maintain determinism across Lisp and JS.
- Respawn uses `find-random-spawn` which loops until it finds an empty tile with at least 2 clear cardinal neighbors and no living player overlap. This is non-deterministic (uses CL `random`), so server is authoritative for spawn positions.
- Crate generation also uses CL `random` (non-deterministic), so the initial map is sent from server to client via serialization.
- Explosions are regenerated fresh each tick from exploding bombs (duration 30) rather than being decremented -- they exist only on the tick a bomb explodes.
