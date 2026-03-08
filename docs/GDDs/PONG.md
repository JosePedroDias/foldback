# Pong Game Design Document

## Overview

Pong is the tutorial game for FoldBack -- the simplest game in the project. Two players control vertical paddles on opposite sides of the table, hitting a ball back and forth. First to 11 points wins.

## Core Mechanics

### Match Flow
- **Players**: 2 (one per side)
- **Status transitions**: `waiting` -> `active` (when 2 players join) -> `p0-wins` / `p1-wins`
- If a player disconnects during an active game, status reverts to `waiting`
- On transition to `active`, ball resets to center serving rightward (vx = +80)

### Scoring
- A goal is scored when the ball exits the left or right boundary (|x| >= TABLE_W/2 = 6000)
- Ball exiting left: side 1 (right paddle) scores
- Ball exiting right: side 0 (left paddle) scores
- After a goal, ball resets to center and serves toward the player who was scored on
- First to 11 wins

### Reset
On goal or game start: all paddle y-positions reset to 0, ball resets to (0,0) with vy=0 and vx = serve_direction * BALL_SPEED.

## Constants (Fixed-Point, scale 1000)

| Constant | Value | Meaning |
|---|---|---|
| TABLE_W | 12000 | Table width (12.0 units) |
| TABLE_H | 8000 | Table height (8.0 units) |
| PADDLE_X | 5500 | Paddle fixed x-position (5.5 units from center) |
| PADDLE_HALF_H | 750 | Paddle half-height (total height = 1.5 units) |
| BALL_R | 150 | Ball radius (0.15 units) |
| BALL_SPEED | 80 | Initial ball vx per tick |
| MAX_VY | 120 | Maximum vertical speed after paddle bounce |
| MAX_SCORE | 11 | Points to win |

## State Shape

```
{
  tick,
  players: {
    id: { id, side, x, y, sc }
  },
  ball: { x, y, vx, vy },
  status   // "waiting" | "active" | "p0-wins" | "p1-wins"
}
```

- **side 0** = left paddle (x = -5500)
- **side 1** = right paddle (x = +5500)
- `sc` = score for that player

## Controls

**Input format**: `(:ty <target_y> :t <tick>)`

Paddles move vertically to the target y-position each tick. The paddle x-position is fixed. The target y is clamped to keep the paddle within the table:
- min_y = -TABLE_H/2 + PADDLE_HALF_H = -3250
- max_y = TABLE_H/2 - PADDLE_HALF_H = 3250

Paddle position is set directly to the clamped target (no velocity/interpolation).

## Physics

### Ball Movement
Each tick the ball moves by (vx, vy). No friction is applied.

### Wall Bounce (Top/Bottom)
- If ball top (y + BALL_R) >= TABLE_H/2: clamp y, negate vy
- If ball bottom (y - BALL_R) <= -TABLE_H/2: clamp y, negate vy

### Paddle Collision
Checked only when the ball is moving toward a paddle (vx < 0 for left, vx > 0 for right).

**Conditions** (example for left paddle at x = -5500):
1. Ball left edge (bx - BALL_R) has reached or passed the paddle line
2. Ball center (bx) has not gone past the paddle (prevents catching a missed ball)
3. Ball vertically overlaps the paddle (ball AABB intersects paddle AABB)

**On hit**:
1. Ball x is corrected to paddle_edge + BALL_R
2. vx is negated (ball reverses direction)
3. vy is set based on relative hit position: `rel_y = (ball_y - paddle_y) / PADDLE_HALF_H`, clamped to [-1, 1], then `vy = rel_y * MAX_VY`. Center hit = 0 vy, edge hit = +/-120 vy.

### Goal Detection
- Ball x <= -TABLE_W/2 (-6000): side 1 scores, ball resets serving left (toward scored-on player)
- Ball x >= TABLE_W/2 (6000): side 0 scores, ball resets serving right

## Implementation Files

- **Lisp server**: `src/games/pong.lisp`
- **JS client logic**: `gateway/pong/logic.js`
- **JS client entry**: `gateway/pong/index.js`

## Key Implementation Notes

- Paddle collision uses a one-sided check: the ball must not have already passed the paddle line. This prevents the paddle from "catching" a ball that was already missed.
- The ball has no friction -- it maintains constant speed between paddle hits. Speed changes only come from vy adjustments on paddle bounce.
- The serve direction after a goal points toward the player who was scored on (ball goes to the losing side).
