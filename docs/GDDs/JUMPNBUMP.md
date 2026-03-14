# Jump 'n Bump Game Design Document

## Overview

Jump 'n Bump is a side-scrolling platformer deathmatch inspired by the classic DOS game. Players control rabbits on a fixed 22x17 tile map, jumping on each other's heads to score kills. Respawn is immediate. There is no win condition -- it is an ongoing freeform deathmatch.

## Core Mechanics

### Map
- **Size**: 22 tiles wide x 17 tiles tall
- **Tile size**: 16000 FP (16 pixels)
- **Viewport**: 400x256 pixels (352x272 in tile units)
- **Tile types**:
  - 0 = air (passable)
  - 1 = solid (ground/walls, collidable)
  - 2 = water (decorative/passable)
  - 3 = ice (solid, with reduced friction)
- **Map data**: hardcoded as a 2D array (`+jnb-map+`), not generated

### Player
- **Size**: 16000 FP x 16000 FP (one tile, 16x16 pixels)
- **Health**: 100 (alive) or 0 (dead/squished)
- **Direction**: 0 = right, 1 = left
- **Respawn**: immediate on next tick after death, at a random empty tile above a solid or ice tile (deterministic via seeded LCG)

### Combat (Squish)
A player kills another by landing on their head. All conditions must be true:
1. Attacker's vy > 0 (falling downward)
2. Attacker's y < target's y (attacker is above)
3. AABB overlap between both players (16000x16000 boxes)

On squish:
- Target's health set to 0 (killed, respawns next tick)
- Attacker gets a bounce: vy set to -6000 (jump force)

### Movement
- **Acceleration**: 250 FP/tick when directional input is held
- **Max horizontal speed**: 1500 FP/tick
- **Friction**: applied every tick before acceleration
  - Ground/ice below: `vx = vx * friction / 1000`
  - Normal friction: 900 (0.9 -- strong damping)
  - Ice friction: 995 (0.995 -- very slippery)
- **Gravity**: 500 FP/tick added to vy every tick
- **Jump force**: -6000 FP (upward impulse)
- **Jumping**: only allowed when on ground (tile below feet is solid or ice)

### Screen Bounds
- X is clamped to [0, 336000] (22*16000 - 16000 = 336000). No wrapping.
- Y is unclamped (players can fall off the bottom -- though the map has a solid floor).

## Constants (Fixed-Point, scale 1000)

| Constant | Value | Meaning |
|---|---|---|
| TILE_SIZE | 16000 | Tile dimensions (16 pixels) |
| PLAYER_SIZE | 16000 | Player bounding box (1 tile) |
| GRAVITY | 500 | Downward acceleration per tick |
| JUMP_FORCE | -6000 | Upward velocity on jump |
| ACCELERATION | 250 | Horizontal acceleration per tick |
| MAX_SPEED | 1500 | Maximum horizontal velocity |
| FRICTION | 900 | Ground friction multiplier (0.9) |
| ICE_FRICTION | 995 | Ice friction multiplier (0.995) |

## State Shape

```
{
  tick,
  players: {
    id: { id, x, y, vx, vy, h, dir, on-ground }
  },
  custom-state: {
    seed    // LCG seed for deterministic spawns
  }
}
```

- `h`: health (100 = alive, 0 = dead)
- `dir`: facing direction (0 = right, 1 = left)
- `on-ground`: boolean, true if standing on solid/ice

## Controls

**Input format**: `{"DX": -1|0|1, "JUMP": true|false, "TICK": <tick>}`

- `dx`: horizontal movement direction (-1 = left, 0 = none, 1 = right)
- `jump`: when truthy and player is on ground, apply jump force

## Physics

### Update Order (per player, per tick)
1. **Friction**: apply friction to vx based on tile below (ice = 995, other = 900)
2. **Horizontal input**: if dx != 0, set direction and add acceleration (clamped to max speed)
3. **Gravity**: add GRAVITY to vy
4. **Compute new position**: nx = x + vx, ny = y + vy
5. **Jump check**: if jump input and on-ground, set vy = JUMP_FORCE, recalculate ny, clear on-ground
6. **Ground collision**: if vy > 0 and tile below is solid/ice, snap y to tile top, set vy = 0
7. **Wall collision**: check tiles at player mid-height on left and right; if solid/ice, push player out and set vx = 0
8. **X clamping**: clamp x to [0, 336000]

After all players are updated:

9. **Squish check**: for each pair of players, check kill conditions (vy > 0, above target, AABB overlap)

### Ground Detection
"On ground" is determined by checking the two tiles below the player's feet:
- `below_left = getTile(nx, ny + PLAYER_SIZE)`
- `below_right = getTile(nx + PLAYER_SIZE, ny + PLAYER_SIZE)`
- On ground if either is solid (1) or ice (3)

### Wall Collision
Checked at the player's vertical midpoint (ny + PLAYER_SIZE/2):
- Left side: `getTile(nx, ny + PLAYER_SIZE/2)` -- if solid/ice, snap x to next tile boundary rightward
- Right side: `getTile(nx + PLAYER_SIZE, ny + PLAYER_SIZE/2)` -- if solid/ice, snap x to tile boundary leftward minus PLAYER_SIZE

### Tile Lookup
`getTile(fpx, fpy)` converts to tile indices via `floor(fpx / 16000)`. Out-of-bounds returns 0 (air).

## Respawn

When a player's health is 0, they respawn immediately on the next tick:
1. Use seeded LCG (`fb-rand-int`) to pick random x (0-21) and y (0-14) tile coordinates
2. Check: tile at (x, y) must be air (0) AND tile at (x, y+1) must be solid (1) or ice (3)
3. If invalid, retry with updated seed (up to 1000 attempts)
4. Spawn at pixel position (tx * 16000, ty * 16000) with zero velocity and random direction

## Implementation Files

- **Lisp server**: `src/games/jumpnbump.lisp`
- **JS client logic**: `gateway/jumpnbump/logic.js`
- **JS client entry**: `gateway/jumpnbump/index.js`

## Key Implementation Notes

- The map is hardcoded (not generated), so the client does not need to receive it from the server.
- Friction is applied BEFORE acceleration each tick. This means friction applies to the previous tick's velocity, then new input is added on top.
- The squish check happens after all players have moved, using the post-movement positions. This means two players moving toward each other can result in a squish in the same tick.
- Water tiles (type 2) are passable and have no gameplay effect -- they are purely visual.
- Ice tiles (type 3) are solid (collidable like walls/ground) but apply reduced friction (995 vs 900), making them very slippery.
- The deterministic PRNG seed is shared state -- each spawn consumes seed values, so spawn order matters for determinism.
- Jump input is checked AFTER computing the tentative new position but BEFORE ground collision resolution. If the player is on ground, jump overrides the vy and recalculates ny.
