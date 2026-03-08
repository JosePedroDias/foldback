# Air Hockey Game Design Document

## Overview

Air Hockey is a 2-player competitive arcade game. Players control circular paddles to hit a puck into the opponent's goal. The table has rounded corners and goals at the top and bottom edges. First to 11 goals wins.

## Core Mechanics

### Match Flow
- **Players**: 2 (one per side)
- **Status transitions**: `waiting` -> `active` (when 2 players join) -> `p0-wins` / `p1-wins`
- If a player disconnects during an active game, status reverts to `waiting`
- On transition to `active`, paddles reset to starting positions (center of their half), puck resets to (0,0)

### Scoring
- Puck entering the top goal: side 1 (bottom player) scores
- Puck entering the bottom goal: side 0 (top player) scores
- After a goal, positions reset (paddles to half-center, puck to origin)
- First to 11 wins

### Sides and Starting Positions
- **Side 0** = top half (starts at y = -4000)
- **Side 1** = bottom half (starts at y = +4000)

## Constants (Fixed-Point, scale 1000)

| Constant | Value | Meaning |
|---|---|---|
| TABLE_WIDTH | 8000 | Table width (8.0 units) |
| TABLE_HEIGHT | 12000 | Table height (12.0 units) |
| PADDLE_RADIUS | 400 | Paddle circle radius |
| PUCK_RADIUS | 300 | Puck circle radius |
| GOAL_WIDTH | 2000 | Goal opening width (+-1000 from center) |
| CORNER_RADIUS | 1000 | Rounded corner radius |
| FRICTION | 990 | Puck friction per tick (0.99) |
| BOUNCE | 800 | Wall bounce coefficient (0.8) |
| MAX_SCORE | 11 | Goals to win |

## State Shape

```
{
  tick,
  players: {
    id: { id, side, x, y, vx, vy, score }
  },
  puck: { x, y, vx, vy },
  status   // "waiting" | "active" | "p0-wins" | "p1-wins"
}
```

## Controls

**Input format**: `(:tx <target_x> :ty <target_y> :t <tick>)`

Paddles use 1:1 positional tracking -- the paddle moves directly to the target position (mouse/touch). The velocity (vx, vy) is derived as the delta from previous position to the new clamped position.

**Paddle constraints**:
- x: clamped to [-TABLE_WIDTH/2 + PADDLE_RADIUS, TABLE_WIDTH/2 - PADDLE_RADIUS] = [-3600, 3600]
- y (side 0, top): clamped to [-TABLE_HEIGHT/2 + PADDLE_RADIUS, -PADDLE_RADIUS] = [-5600, -400]
- y (side 1, bottom): clamped to [PADDLE_RADIUS, TABLE_HEIGHT/2 - PADDLE_RADIUS] = [400, 5600]
- Paddles cannot cross the center line

## Physics

### Table Geometry
The table boundary is built from line segments:
- **Straight walls**: left and right sides, plus partial top/bottom edges (excluding goal openings)
- **Goals**: top center and bottom center segments, each GOAL_WIDTH wide
- **Corners**: 4 rounded corners, each approximated by 6 line segments (arc subdivided at 15-degree intervals)

Segments are typed as `:wall`, `:goal-top`, or `:goal-bottom`.

### Puck Movement
Each tick:
1. Apply friction: `vx = fpMul(vx, 990)`, `vy = fpMul(vy, 990)`
2. Move: `x += vx`, `y += vy`

### Out-of-Bounds Safety Check
If `|puck.x| > 4400` or `|puck.y| > 6600`, the puck has escaped -- reset all positions (failsafe).

### Paddle-Puck Collision (Circle-Circle)
When the puck overlaps a paddle:
1. Compute push direction and overlap using `fp-push-circles`
2. Push puck out of paddle by overlap along normal
3. Set puck velocity to: `paddle.v + normal * 50` (momentum transfer with a fixed impulse of 50)

### Wall-Puck Collision (Circle-Segment)
For each wall segment:
1. Find closest point on segment to puck center
2. If distance < PUCK_RADIUS:
   - **Wall segments**: reflect velocity (subtract 2 * dot(v, normal) * normal), apply bounce coefficient (0.8), push puck out of wall
   - **Goal-top segment**: side 1 scores
   - **Goal-bottom segment**: side 0 scores

### Wall Bounce Formula
```
dot = vx*nx + vy*ny
vx = (vx - 2*nx*dot) * BOUNCE
vy = (vy - 2*ny*dot) * BOUNCE
```

## Implementation Files

- **Lisp server**: `src/games/airhockey.lisp`
- **JS client logic**: `gateway/airhockey/logic.js`
- **JS client entry**: `gateway/airhockey/index.js`

## Key Implementation Notes

- Table segments are generated once at load time and stored in `*ah-segments*`. The corners use floating-point trigonometry to compute vertex positions, then convert to fixed-point.
- Paddle velocity is computed as the difference between new and old position each tick (not from input). This means faster mouse movement = harder hits.
- The OOB check (4400/6600) is a safety net -- if the puck somehow escapes the table boundary, the game resets rather than letting it fly off.
- Goal detection happens as part of the wall-segment collision loop -- goals are just special-typed segments.
- Multiple paddle collisions are checked sequentially; the last paddle to collide wins if both overlap simultaneously.
