# Tic-Tac-Toe Game Design Document

## Overview

Tic-Tac-Toe is the simplest game in FoldBack and the first to use **authoritative-only mode** (no client-side prediction). Two players take turns placing marks on a 3x3 grid. First to get three in a row wins. It demonstrates that FoldBack's server infrastructure works for turn-based games without any CSP complexity.

## Core Mechanics

### Match Flow
- **Players**: 2 (side 0 = X, side 1 = O)
- **Status transitions**: `waiting` -> `active` (when 2 players join) -> `x-wins` / `o-wins` / `draw`
- If a player disconnects during a non-waiting state, the board resets and status reverts to `waiting`
- Either player can request a rematch after a game ends, which resets to `active`

### Turns
- X (side 0) always goes first
- Players alternate turns; only the current turn's player can place a mark
- Invalid moves are silently ignored (wrong turn, occupied cell, out-of-range cell)

### Win Detection
Three in a row on any of 8 lines:
- 3 rows: (0,1,2), (3,4,5), (6,7,8)
- 3 columns: (0,3,6), (1,4,7), (2,5,8)
- 2 diagonals: (0,4,8), (2,4,6)

### Draw
If all 9 cells are filled and no player has three in a row, the game is a draw.

## State Shape

```
{
  tick,
  players: {
    id: { id, side }
  },
  board: [9 cells],   // null = empty, 0 = X, 1 = O
  turn,                // 0 (X's turn) or 1 (O's turn)
  status               // "waiting" | "active" | "x-wins" | "o-wins" | "draw"
}
```

Board layout (indices):
```
 0 | 1 | 2
-----------
 3 | 4 | 5
-----------
 6 | 7 | 8
```

## Controls

**Move**: `{"CELL": <0-8>}` -- place a mark on the given cell.

**Rematch**: `{"TYPE": "REMATCH"}` -- request a new game after win/loss/draw.

No TICK field is needed in inputs. The server assigns incoming inputs to the next tick automatically, which is the standard behavior for authoritative-only games where the client does not track tick numbers.

## Server Configuration

- **Tick rate**: 10 Hz (turn-based games need minimal tick rate)
- **No fixed-point math**: all values are discrete integers or null
- **No physics**: no collision, no movement, no continuous simulation

## Implementation Files

- **Lisp server**: `src/games/tictactoe.lisp`
- **JS client entry**: `gateway/tictactoe/index.js` (contains applyDelta, sync, render, and input handling)
- **No `logic.js`**: authoritative-only games have no JS simulation to mirror

## Key Implementation Notes

- The client uses `prediction: false` in `createGameClient`, so no `updateFn` is provided. The client sends actions and renders whatever the server broadcasts.
- Input is event-driven: a click sets a pending cell, `getInput` returns it once and clears it. This avoids sending duplicate moves on consecutive ticks.
- The board is stored as an `fset:seq` (persistent vector) on the server and serialized as a JSON array of 9 elements (null, 0, or 1).
- The `inputs` parameter to `ttt-update` can be nil on ticks with no player input. All iteration over inputs must guard against this.
