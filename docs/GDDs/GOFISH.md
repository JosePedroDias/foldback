# Go Fish Game Design Document

## Overview

Go Fish is the second **authoritative-only** game in FoldBack and the first to use **hidden state** — each player sees their own hand but only card counts for opponents. It supports 2–5 players and introduces a **ready-up phase** for variable player counts. The server performs per-player serialization, sending different JSON to each client.

## Core Mechanics

### Match Flow
- **Players**: 2–5 (seats 0–4, assigned on join)
- **Status transitions**: `waiting` → `ready-up` (2+ players) → `active` (all ready) → `game-over` (books complete or deck exhausted)
- If any player disconnects during an active game, the game resets (to `ready-up` if 2+ remain, `waiting` if fewer)
- Any player can request a rematch after game over, returning to `ready-up`

### Ready-Up
- When 2+ players are connected, the game enters `ready-up`
- Each player must click a READY button to signal readiness
- Once all connected players are ready, the game starts
- New players joining during `ready-up` do not reset others' readiness

### Dealing
- Standard 52-card deck (13 ranks × 4 suits)
- **2–3 players**: 7 cards each
- **4–5 players**: 5 cards each
- Remaining cards form the draw pile
- Shuffle uses a deterministic LCG (`fb-rand-int`) seeded per game
- Any 4-of-a-kind dealt in initial hands is automatically laid down as a book

### Turns
- Seat 0 goes first
- On your turn, you must:
  1. Select a rank from your hand
  2. Select an opponent to ask (auto-targeted in 2-player games)
- You can only ask for ranks you hold at least one card of
- Invalid asks are silently ignored (wrong turn, rank not in hand, asking yourself, out-of-range target)

### Asking
- **Opponent has the rank**: they give all cards of that rank to you. You go again.
- **Opponent doesn't have it ("Go Fish")**: draw one card from the deck.
  - If the drawn card matches the rank you asked for, you go again.
  - Otherwise, turn passes to the next player (who still has cards).

### Books
- When you hold all 4 cards of a rank, they are automatically laid down as a book and removed from your hand.
- Books are visible to all players.

### Game End
The game ends when:
- All 13 books have been collected (all 52 cards accounted for), or
- The deck is empty and any player's hand is empty

The player with the most books wins.

### Empty Hand During Play
If your hand becomes empty (from books) and the deck still has cards, you draw one card to continue.

## State Shape

### Server State (Lisp)
```
{
  tick,
  players: { id: { id, seat, ready } },
  hands:   { seat: fset:seq of cards },    // card = { rank, suit }
  deck:    fset:seq of cards,
  books:   { seat: list of rank integers },
  turn,                                      // seat index of current turn
  status,                                    // :waiting | :ready-up | :active | :game-over
  last-ask,                                  // { seat, target, rank, got, drew-match? }
  seed                                       // RNG seed
}
```

### Wire State (per-player JSON)
```json
{
  "TICK": 42,
  "STATUS": "ACTIVE",
  "TURN": 0,
  "DECK_COUNT": 30,
  "HANDS": {
    "0": [{"RANK": 1, "SUIT": 0}, {"RANK": 5, "SUIT": 2}],
    "1": 5
  },
  "BOOKS": {
    "0": [13],
    "1": []
  },
  "LAST_ASK": {
    "SEAT": 0, "TARGET": 1, "RANK": 1, "GOT": 2
  },
  "PLAYERS": [
    {"ID": 0, "SEAT": 0, "READY": true},
    {"ID": 1, "SEAT": 1, "READY": false}
  ]
}
```

**Hidden state**: in the `HANDS` object, your own seat contains an array of card objects (`{RANK, SUIT}`). Other seats contain just an integer (card count). Each player receives a different version of this field.

## Controls

**Ask**: `{"RANK": <1-13>, "TARGET": <seat>}` — ask the target player for all cards of the given rank.

**Ready**: `{"TYPE": "READY"}` — signal readiness during `ready-up`.

**Rematch**: `{"TYPE": "REMATCH"}` — request a new game after `game-over`.

No TICK field is needed in inputs. The server assigns incoming inputs to the next tick automatically.

## Card Representation

- **Rank**: 1–13 (1=A, 2–10, 11=J, 12=Q, 13=K)
- **Suit**: 0–3 (0=♠, 1=♥, 2=♦, 3=♣)

## Server Configuration

- **Tick rate**: 10 Hz (turn-based)
- **Initial seed**: passed via `:initial-custom-state (fset:map (:seed 12345))`
- **No fixed-point math**: all values are discrete integers
- **No physics**: no collision, no movement, no continuous simulation

## Client Features

### Two-Step Ask (3+ players)
1. Click a card to select a rank (highlighted in yellow)
2. Click an opponent to ask (dashed border indicates valid targets)
3. If the selected rank leaves your hand between steps (server update), the selection is automatically cleared

### One-Click Ask (2 players)
Clicking a card immediately asks the only opponent — no target selection needed.

### Visual Feedback (Flash Highlights)
- **Green flash on your cards**: you received cards (successful ask) or drew a matching card
- **Red flash on your cards**: someone took cards from you
- **Orange flash on your whole hand**: Go Fish, drew a non-matching card
- **Green/red glow on opponents**: they gained/lost cards
- Flashes fade out over 1.5 seconds

### Last Ask Message
A text message in the center shows what happened: who asked whom for what rank, how many cards changed hands, and whether a drawn card matched.

## Implementation Files

- **Lisp server**: `src/games/gofish.lisp`
- **JS client entry**: `gateway/gofish/index.js` (contains applyDelta, sync, render, input handling, flash system)
- **No `logic.js`**: authoritative-only games have no JS simulation to mirror
- **Schemas**: `schemas/gofish/client-to-server.schema.json`, `schemas/gofish/server-to-client.schema.json`

## Key Implementation Notes

- The client uses `prediction: false` in `createGameClient`, so no `updateFn` is provided.
- Per-player serialization is achieved by passing `player-id` to the serialize function. The server broadcast loop in `server.lisp` passes each client's player ID.
- The `LAST_ASK` field is only present in the JSON when non-nil. The `DREW_MATCH` sub-field is only included when true.
- The `selectedRank` UI state is cleared automatically when the turn changes or the rank leaves the player's hand, preventing stale input from being sent.
- Cards in the client hand are sorted by rank (then suit) for readability.
