/**
 * Tic-Tac-Toe cross-platform test (JS side).
 * Tests the client-side wire protocol handling: applyDelta, sync.
 */

let pass = 0;
let fail = 0;

function assert(condition, message) {
    if (!condition) {
        console.error("  FAIL: " + message);
        fail++;
    } else {
        console.log("  PASS: " + message);
        pass++;
    }
}

// --- Inline client functions ---

function tttApplyDelta(baseState, delta) {
    return {
        tick: delta.TICK ?? baseState.tick,
        status: delta.STATUS ?? baseState.status,
        turn: delta.TURN ?? baseState.turn,
        board: delta.BOARD ?? baseState.board ?? [null,null,null,null,null,null,null,null,null],
        players: delta.PLAYERS
            ? Object.fromEntries(delta.PLAYERS.map(p => [p.ID, { id: p.ID, side: p.SIDE }]))
            : baseState.players,
    };
}

function tttSync(localState, serverState) {
    localState.tick = serverState.tick;
    localState.status = serverState.status;
    localState.turn = serverState.turn;
    localState.board = serverState.board;
    localState.players = serverState.players;
}

// ============================================================

console.log("\n=== Tic-Tac-Toe Cross-Platform Tests (JS) ===");

// --- applyDelta: WAITING ---
console.log("\n-- applyDelta: WAITING --");
{
    const base = { tick: 0, status: 'WAITING', turn: 0, board: [null,null,null,null,null,null,null,null,null], players: {} };
    const delta = {
        TICK: 1, STATUS: "WAITING", TURN: 0,
        BOARD: [null,null,null,null,null,null,null,null,null],
        PLAYERS: [{ ID: 0, SIDE: 0 }],
    };
    const s = tttApplyDelta(base, delta);
    assert(s.tick === 1, "tick applied");
    assert(s.status === "WAITING", "status is WAITING");
    assert(s.players[0].side === 0, "player 0 is side 0 (X)");
}

// --- applyDelta: ACTIVE ---
console.log("\n-- applyDelta: ACTIVE --");
{
    const base = { tick: 1, status: 'WAITING', turn: 0, board: [null,null,null,null,null,null,null,null,null], players: {} };
    const delta = {
        TICK: 2, STATUS: "ACTIVE", TURN: 0,
        BOARD: [null,null,null,null,null,null,null,null,null],
        PLAYERS: [
            { ID: 0, SIDE: 0 },
            { ID: 1, SIDE: 1 },
        ],
    };
    const s = tttApplyDelta(base, delta);
    assert(s.status === "ACTIVE", "status is ACTIVE");
    assert(Object.keys(s.players).length === 2, "2 players");
    assert(s.players[0].side === 0, "player 0 is X");
    assert(s.players[1].side === 1, "player 1 is O");
    assert(s.turn === 0, "X goes first");
}

// --- applyDelta: moves on board ---
console.log("\n-- applyDelta: board moves --");
{
    const base = { tick: 2, status: 'ACTIVE', turn: 0, board: [null,null,null,null,null,null,null,null,null], players: {} };
    const delta = {
        TICK: 3, STATUS: "ACTIVE", TURN: 1,
        BOARD: [0, null, null, null, null, null, null, null, null],
        PLAYERS: [
            { ID: 0, SIDE: 0 },
            { ID: 1, SIDE: 1 },
        ],
    };
    const s = tttApplyDelta(base, delta);
    assert(s.board[0] === 0, "cell 0 has X");
    assert(s.board[1] === null, "cell 1 empty");
    assert(s.turn === 1, "turn switched to O");
}

// --- applyDelta: X_WINS ---
console.log("\n-- applyDelta: X_WINS --");
{
    const base = { tick: 5, status: 'ACTIVE', turn: 0, board: [0,0,null,1,1,null,null,null,null], players: {} };
    const delta = {
        TICK: 6, STATUS: "X_WINS", TURN: 0,
        BOARD: [0, 0, 0, 1, 1, null, null, null, null],
        PLAYERS: [
            { ID: 0, SIDE: 0 },
            { ID: 1, SIDE: 1 },
        ],
    };
    const s = tttApplyDelta(base, delta);
    assert(s.status === "X_WINS", "X wins");
    assert(s.board[2] === 0, "winning move at cell 2");
}

// --- applyDelta: DRAW ---
console.log("\n-- applyDelta: DRAW --");
{
    const base = { tick: 9, status: 'ACTIVE', turn: 0, board: [0,1,0,1,0,0,null,0,1], players: {} };
    const delta = {
        TICK: 10, STATUS: "DRAW", TURN: 0,
        BOARD: [0, 1, 0, 1, 0, 0, 1, 0, 1],
    };
    const s = tttApplyDelta(base, delta);
    assert(s.status === "DRAW", "draw");
    assert(s.board.every(c => c !== null), "all cells filled");
}

// --- sync overwrites localState ---
console.log("\n-- sync --");
{
    const local = { tick: 0, status: 'WAITING', turn: 0, board: [null,null,null,null,null,null,null,null,null], players: {} };
    const server = {
        tick: 5, status: 'ACTIVE', turn: 1,
        board: [0, null, 1, null, 0, null, null, null, null],
        players: { 0: { id: 0, side: 0 }, 1: { id: 1, side: 1 } },
    };
    tttSync(local, server);
    assert(local.tick === 5, "tick synced");
    assert(local.status === 'ACTIVE', "status synced");
    assert(local.turn === 1, "turn synced");
    assert(local.board[0] === 0, "board synced (X at 0)");
    assert(local.board[2] === 1, "board synced (O at 2)");
    assert(local.board[1] === null, "board synced (empty at 1)");
}

// --- delta without PLAYERS preserves existing ---
console.log("\n-- delta without PLAYERS --");
{
    const base = {
        tick: 3, status: 'ACTIVE', turn: 0,
        board: [0, null, null, null, null, null, null, null, null],
        players: { 0: { id: 0, side: 0 }, 1: { id: 1, side: 1 } },
    };
    const delta = {
        TICK: 4, STATUS: "ACTIVE", TURN: 1,
        BOARD: [0, 1, null, null, null, null, null, null, null],
    };
    const s = tttApplyDelta(base, delta);
    assert(Object.keys(s.players).length === 2, "players preserved from base");
    assert(s.players[0].side === 0, "player 0 side preserved");
}

// --- player side detection ---
console.log("\n-- player side detection --");
{
    const state = {
        players: { 0: { id: 0, side: 0 }, 1: { id: 1, side: 1 } },
        turn: 0,
    };
    const mySide0 = state.players[0]?.side;
    const mySide1 = state.players[1]?.side;
    assert(mySide0 === 0, "player 0 is X (side 0)");
    assert(mySide1 === 1, "player 1 is O (side 1)");
    assert(state.turn === mySide0, "it's X's turn");
}

// --- Summary ---
console.log(`\n=== Tic-Tac-Toe Cross-Platform Results: ${pass} passed, ${fail} failed ===`);
if (fail > 0) process.exit(1);
