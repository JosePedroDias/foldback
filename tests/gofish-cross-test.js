/**
 * Go Fish cross-platform test (JS side).
 * Tests the client-side wire protocol handling: applyDelta, sync, helpers.
 * Verifies that server JSON is correctly interpreted by the client.
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

// --- Inline the client functions (they live in an ES module with DOM deps) ---

function gfApplyDelta(baseState, delta) {
    return {
        tick: delta.TICK ?? baseState.tick,
        status: delta.STATUS ?? baseState.status,
        turn: delta.TURN ?? baseState.turn,
        deckCount: delta.DECK_COUNT ?? baseState.deckCount ?? 0,
        hands: delta.HANDS ?? baseState.hands ?? {},
        books: delta.BOOKS ?? baseState.books ?? {},
        lastAsk: delta.LAST_ASK !== undefined ? delta.LAST_ASK : baseState.lastAsk,
        players: delta.PLAYERS
            ? Object.fromEntries(delta.PLAYERS.map(p => [p.ID, { id: p.ID, seat: p.SEAT, ready: p.READY }]))
            : baseState.players,
    };
}

function gfSync(localState, serverState) {
    localState.tick = serverState.tick;
    localState.status = serverState.status;
    localState.turn = serverState.turn;
    localState.deckCount = serverState.deckCount;
    localState.hands = serverState.hands;
    localState.books = serverState.books;
    localState.lastAsk = serverState.lastAsk;
    localState.players = serverState.players;
}

function getMyHand(state, mySeat) {
    if (mySeat === null || mySeat === undefined) return [];
    const hand = state.hands?.[mySeat];
    if (!Array.isArray(hand)) return [];
    return hand;
}

function getSeatForPlayer(state, playerId) {
    const p = state.players?.[playerId];
    return p?.seat ?? null;
}

function getNumPlayers(state) {
    return Object.keys(state.players || {}).length;
}

function getUniqueRanks(hand) {
    const ranks = new Set(hand.map(c => c.RANK));
    return [...ranks].sort((a, b) => a - b);
}

// ============================================================

console.log("\n=== Go Fish Cross-Platform Tests (JS) ===");

// --- applyDelta: WAITING state ---
console.log("\n-- applyDelta: WAITING --");
{
    const base = { tick: 0, status: 'WAITING', turn: 0, deckCount: 0, hands: {}, books: {}, lastAsk: null, players: {} };
    const delta = {
        TICK: 1, STATUS: "WAITING", TURN: 0, DECK_COUNT: 0,
        HANDS: {}, BOOKS: {},
        PLAYERS: [{ ID: 0, SEAT: 0, READY: false }],
    };
    const s = gfApplyDelta(base, delta);
    assert(s.tick === 1, "tick applied");
    assert(s.status === "WAITING", "status is WAITING");
    assert(s.players[0].seat === 0, "player 0 has seat 0");
    assert(s.players[0].ready === false, "player 0 not ready");
}

// --- applyDelta: READY_UP state ---
console.log("\n-- applyDelta: READY_UP --");
{
    const base = { tick: 1, status: 'WAITING', turn: 0, deckCount: 0, hands: {}, books: {}, lastAsk: null, players: {} };
    const delta = {
        TICK: 2, STATUS: "READY_UP", TURN: 0, DECK_COUNT: 0,
        HANDS: {}, BOOKS: {},
        PLAYERS: [
            { ID: 0, SEAT: 0, READY: true },
            { ID: 1, SEAT: 1, READY: false },
        ],
    };
    const s = gfApplyDelta(base, delta);
    assert(s.status === "READY_UP", "status is READY_UP");
    assert(Object.keys(s.players).length === 2, "2 players");
    assert(s.players[0].ready === true, "player 0 ready");
    assert(s.players[1].ready === false, "player 1 not ready");
}

// --- applyDelta: ACTIVE with hidden state ---
console.log("\n-- applyDelta: ACTIVE (hidden state) --");
{
    const base = { tick: 2, status: 'READY_UP', turn: 0, deckCount: 0, hands: {}, books: {}, lastAsk: null, players: {} };
    // Simulates what player 0 would receive: own hand as card array, opponent as count
    const delta = {
        TICK: 3, STATUS: "ACTIVE", TURN: 0, DECK_COUNT: 38,
        HANDS: {
            "0": [{ RANK: 1, SUIT: 0 }, { RANK: 5, SUIT: 2 }, { RANK: 5, SUIT: 3 }],
            "1": 7,
        },
        BOOKS: { "0": [], "1": [] },
        PLAYERS: [
            { ID: 0, SEAT: 0, READY: true },
            { ID: 1, SEAT: 1, READY: true },
        ],
    };
    const s = gfApplyDelta(base, delta);
    assert(s.status === "ACTIVE", "status is ACTIVE");
    assert(s.deckCount === 38, "deck count is 38");
    assert(Array.isArray(s.hands["0"]), "own hand is array");
    assert(s.hands["0"].length === 3, "own hand has 3 cards");
    assert(s.hands["0"][0].RANK === 1, "first card rank is 1 (Ace)");
    assert(s.hands["0"][0].SUIT === 0, "first card suit is 0 (spade)");
    assert(typeof s.hands["1"] === 'number', "opponent hand is count");
    assert(s.hands["1"] === 7, "opponent has 7 cards");
}

// --- getMyHand and getSeatForPlayer ---
console.log("\n-- getMyHand / getSeatForPlayer --");
{
    const state = {
        hands: {
            "0": [{ RANK: 1, SUIT: 0 }, { RANK: 2, SUIT: 1 }],
            "1": 5,
        },
        players: {
            0: { id: 0, seat: 0 },
            1: { id: 1, seat: 1 },
        },
    };

    assert(getSeatForPlayer(state, 0) === 0, "player 0 → seat 0");
    assert(getSeatForPlayer(state, 1) === 1, "player 1 → seat 1");
    assert(getSeatForPlayer(state, 99) === null, "unknown player → null");

    const hand0 = getMyHand(state, 0);
    assert(hand0.length === 2, "seat 0 hand has 2 cards");
    assert(hand0[0].RANK === 1, "seat 0 first card rank");

    const hand1 = getMyHand(state, 1);
    assert(hand1.length === 0, "seat 1 hand is count (not array) → empty");

    const handNull = getMyHand(state, null);
    assert(handNull.length === 0, "null seat → empty hand");
}

// --- getUniqueRanks ---
console.log("\n-- getUniqueRanks --");
{
    const hand = [
        { RANK: 5, SUIT: 0 }, { RANK: 3, SUIT: 1 },
        { RANK: 5, SUIT: 2 }, { RANK: 1, SUIT: 0 },
    ];
    const ranks = getUniqueRanks(hand);
    assert(ranks.length === 3, "3 unique ranks");
    assert(ranks[0] === 1 && ranks[1] === 3 && ranks[2] === 5, "sorted: 1, 3, 5");
}

// --- sync overwrites localState ---
console.log("\n-- sync --");
{
    const local = { tick: 0, status: 'WAITING', turn: 0, deckCount: 0, hands: {}, books: {}, lastAsk: null, players: {} };
    const server = {
        tick: 10, status: 'ACTIVE', turn: 1, deckCount: 30,
        hands: { "0": [{ RANK: 1, SUIT: 0 }], "1": 5 },
        books: { "0": [13], "1": [] },
        lastAsk: { SEAT: 0, TARGET: 1, RANK: 13, GOT: 2 },
        players: { 0: { id: 0, seat: 0 }, 1: { id: 1, seat: 1 } },
    };
    gfSync(local, server);
    assert(local.tick === 10, "tick synced");
    assert(local.status === 'ACTIVE', "status synced");
    assert(local.turn === 1, "turn synced");
    assert(local.deckCount === 30, "deckCount synced");
    assert(local.hands["0"].length === 1, "hands synced (own)");
    assert(local.hands["1"] === 5, "hands synced (count)");
    assert(local.books["0"][0] === 13, "books synced");
    assert(local.lastAsk.GOT === 2, "lastAsk synced");
}

// --- lastAsk with DREW_MATCH ---
console.log("\n-- lastAsk with DREW_MATCH --");
{
    const base = { tick: 5, status: 'ACTIVE', turn: 0, deckCount: 10, hands: {}, books: {}, lastAsk: null, players: {} };
    const delta = {
        TICK: 6, STATUS: "ACTIVE", TURN: 0, DECK_COUNT: 9,
        HANDS: { "0": [{ RANK: 3, SUIT: 0 }], "1": 4 },
        BOOKS: { "0": [], "1": [] },
        LAST_ASK: { SEAT: 0, TARGET: 1, RANK: 3, GOT: 0, DREW_MATCH: true },
        PLAYERS: [
            { ID: 0, SEAT: 0, READY: true },
            { ID: 1, SEAT: 1, READY: true },
        ],
    };
    const s = gfApplyDelta(base, delta);
    assert(s.lastAsk.GOT === 0, "Go Fish: got 0");
    assert(s.lastAsk.DREW_MATCH === true, "drew matching card");
    assert(s.turn === 0, "same player goes again");
}

// --- GAME_OVER state with books ---
console.log("\n-- GAME_OVER --");
{
    const base = { tick: 100, status: 'ACTIVE', turn: 0, deckCount: 0, hands: {}, books: {}, lastAsk: null, players: {} };
    const delta = {
        TICK: 101, STATUS: "GAME_OVER", TURN: 0, DECK_COUNT: 0,
        HANDS: { "0": [], "1": [] },
        BOOKS: { "0": [1, 2, 3, 4, 5, 6, 7], "1": [8, 9, 10, 11, 12, 13] },
        PLAYERS: [
            { ID: 0, SEAT: 0, READY: true },
            { ID: 1, SEAT: 1, READY: true },
        ],
    };
    const s = gfApplyDelta(base, delta);
    assert(s.status === "GAME_OVER", "status is GAME_OVER");
    assert(s.books["0"].length === 7, "player 0 has 7 books");
    assert(s.books["1"].length === 6, "player 1 has 6 books");

    // Determine winner
    let maxBooks = -1, winner = -1;
    for (let seat = 0; seat < 2; seat++) {
        const bk = s.books[seat]?.length || 0;
        if (bk > maxBooks) { maxBooks = bk; winner = seat; }
    }
    assert(winner === 0, "player 0 wins with most books");
}

// --- Ask flow: client input → server response → client state ---
console.log("\n-- Ask flow: successful ask --");
{
    // Simulate: player 0 has Aces, asks player 1 who also has an Ace
    // Client produces this wire message:
    const wireInput = { RANK: 1, TARGET: 1 };
    assert(wireInput.RANK === 1, "wire: asking for Aces");
    assert(wireInput.TARGET === 1, "wire: asking player at seat 1");

    // Server processes and sends back updated state for player 0:
    const serverResponse = {
        TICK: 10, STATUS: "ACTIVE", TURN: 0, DECK_COUNT: 35,
        HANDS: {
            "0": [
                { RANK: 1, SUIT: 0 }, { RANK: 1, SUIT: 1 }, { RANK: 1, SUIT: 2 },  // had 2, got 1 more
                { RANK: 5, SUIT: 0 },
            ],
            "1": 4,  // had 5, lost 1
        },
        BOOKS: { "0": [], "1": [] },
        LAST_ASK: { SEAT: 0, TARGET: 1, RANK: 1, GOT: 1 },
        PLAYERS: [
            { ID: 0, SEAT: 0, READY: true },
            { ID: 1, SEAT: 1, READY: true },
        ],
    };

    const base = { tick: 9, status: 'ACTIVE', turn: 0, deckCount: 36, hands: {}, books: {}, lastAsk: null, players: {} };
    const s = gfApplyDelta(base, serverResponse);

    assert(s.lastAsk.GOT === 1, "got 1 card");
    assert(s.lastAsk.RANK === 1, "asked for Aces");
    assert(s.lastAsk.SEAT === 0, "asker is seat 0");
    assert(s.lastAsk.TARGET === 1, "target is seat 1");
    assert(s.turn === 0, "turn stays with asker on success");
    assert(s.hands["0"].length === 4, "own hand grew to 4");
    assert(s.hands["0"].filter(c => c.RANK === 1).length === 3, "now has 3 Aces");
    assert(s.hands["1"] === 4, "opponent went from 5 to 4 cards");
}

console.log("\n-- Ask flow: Go Fish --");
{
    const wireInput = { RANK: 7, TARGET: 1 };
    assert(wireInput.RANK === 7, "wire: asking for 7s");

    // Server response: Go Fish, drew a card (not a match)
    const serverResponse = {
        TICK: 11, STATUS: "ACTIVE", TURN: 1, DECK_COUNT: 34,
        HANDS: {
            "0": [
                { RANK: 1, SUIT: 0 }, { RANK: 7, SUIT: 0 },
                { RANK: 9, SUIT: 3 },  // drawn card (not a 7)
            ],
            "1": 5,
        },
        BOOKS: { "0": [], "1": [] },
        LAST_ASK: { SEAT: 0, TARGET: 1, RANK: 7, GOT: 0 },
        PLAYERS: [
            { ID: 0, SEAT: 0, READY: true },
            { ID: 1, SEAT: 1, READY: true },
        ],
    };

    const base = { tick: 10, status: 'ACTIVE', turn: 0, deckCount: 35, hands: {}, books: {}, lastAsk: null, players: {} };
    const s = gfApplyDelta(base, serverResponse);

    assert(s.lastAsk.GOT === 0, "Go Fish: got 0");
    assert(s.lastAsk.DREW_MATCH === undefined, "no drew_match (wasn't a match)");
    assert(s.turn === 1, "turn passed to opponent");
    assert(s.deckCount === 34, "deck shrunk by 1");
    assert(s.hands["0"].length === 3, "drew 1 card");
}

console.log("\n-- Ask flow: Go Fish drew match --");
{
    const serverResponse = {
        TICK: 12, STATUS: "ACTIVE", TURN: 0, DECK_COUNT: 33,
        HANDS: {
            "0": [
                { RANK: 3, SUIT: 0 }, { RANK: 3, SUIT: 1 },  // drew a matching 3
            ],
            "1": 5,
        },
        BOOKS: { "0": [], "1": [] },
        LAST_ASK: { SEAT: 0, TARGET: 1, RANK: 3, GOT: 0, DREW_MATCH: true },
        PLAYERS: [
            { ID: 0, SEAT: 0, READY: true },
            { ID: 1, SEAT: 1, READY: true },
        ],
    };

    const base = { tick: 11, status: 'ACTIVE', turn: 0, deckCount: 34, hands: {}, books: {}, lastAsk: null, players: {} };
    const s = gfApplyDelta(base, serverResponse);

    assert(s.lastAsk.GOT === 0, "Go Fish");
    assert(s.lastAsk.DREW_MATCH === true, "drew a match");
    assert(s.turn === 0, "same player goes again on match");
}

console.log("\n-- Ask flow: book formed --");
{
    // Player 0 had 3 Aces, gets the 4th → book
    const serverResponse = {
        TICK: 13, STATUS: "ACTIVE", TURN: 0, DECK_COUNT: 30,
        HANDS: {
            "0": [{ RANK: 5, SUIT: 0 }],  // Aces removed (book), only 5 remains
            "1": 3,
        },
        BOOKS: { "0": [1], "1": [] },  // book of Aces
        LAST_ASK: { SEAT: 0, TARGET: 1, RANK: 1, GOT: 1 },
        PLAYERS: [
            { ID: 0, SEAT: 0, READY: true },
            { ID: 1, SEAT: 1, READY: true },
        ],
    };

    const base = { tick: 12, status: 'ACTIVE', turn: 0, deckCount: 31, hands: {}, books: {}, lastAsk: null, players: {} };
    const s = gfApplyDelta(base, serverResponse);

    assert(s.books["0"].length === 1, "1 book completed");
    assert(s.books["0"][0] === 1, "book of Aces");
    assert(s.hands["0"].length === 1, "Aces removed from hand");
    assert(s.hands["0"][0].RANK === 5, "only 5 remains");
}

console.log("\n-- Ask flow: wire format for READY/REMATCH --");
{
    // Verify the wire format for non-ask actions
    const readyWire = { TYPE: 'READY' };
    assert(readyWire.TYPE === 'READY', "READY wire format correct");

    const rematchWire = { TYPE: 'REMATCH' };
    assert(rematchWire.TYPE === 'REMATCH', "REMATCH wire format correct");

    const askWire = { RANK: 5, TARGET: 2 };
    assert(askWire.RANK === 5, "ask wire has RANK");
    assert(askWire.TARGET === 2, "ask wire has TARGET");
    assert(askWire.TYPE === undefined, "ask wire has no TYPE");
}

// --- Non-contiguous seats (after rejoin) ---
console.log("\n-- Non-contiguous seats --");
{
    const state = {
        hands: {
            "0": [{ RANK: 1, SUIT: 0 }],
            "2": 3,
        },
        players: {
            5: { id: 5, seat: 0 },
            7: { id: 7, seat: 2 },
        },
    };
    assert(getSeatForPlayer(state, 5) === 0, "player 5 → seat 0");
    assert(getSeatForPlayer(state, 7) === 2, "player 7 → seat 2");
    assert(getNumPlayers(state) === 2, "2 players");
    assert(getMyHand(state, 0).length === 1, "seat 0 has cards");
    assert(getMyHand(state, 2).length === 0, "seat 2 hand is count → empty array");

    // 2-player auto-target: find other seat correctly
    const mySeat = 0;
    let otherSeat = null;
    for (const p of Object.values(state.players)) {
        if (p.seat !== mySeat) { otherSeat = p.seat; break; }
    }
    assert(otherSeat === 2, "auto-target finds seat 2, not seat 1");
}

// --- Integration: parse real Lisp server output ---
console.log("\n-- Integration: real Lisp serialize output --");
{
    const fs = await import('fs');
    const snapshotPath = 'tests/gofish-snapshots.json';
    if (fs.existsSync(snapshotPath)) {
        const snapshots = JSON.parse(fs.readFileSync(snapshotPath, 'utf8'));
        assert(snapshots.length === 5, `loaded ${snapshots.length} snapshots`);

        const base = { tick: 0, status: 'WAITING', turn: 0, deckCount: 0, hands: {}, books: {}, lastAsk: null, players: {} };

        // Snapshot 0: initial ACTIVE state for player 0
        const s0 = gfApplyDelta(base, snapshots[0]);
        assert(s0.status === 'ACTIVE', "snap0: ACTIVE");
        assert(s0.turn === 0, "snap0: turn 0");
        assert(s0.deckCount === 2, "snap0: deck 2");
        assert(Array.isArray(s0.hands["0"]), "snap0: own hand is array");
        assert(s0.hands["0"].length === 3, "snap0: own hand has 3 cards");
        assert(typeof s0.hands["1"] === 'number', "snap0: opponent hand is count");
        assert(s0.hands["1"] === 3, "snap0: opponent has 3 cards");
        assert(s0.lastAsk === null || s0.lastAsk === undefined, "snap0: no lastAsk");

        // Snapshot 1: after successful ask (player 0's view)
        const s1 = gfApplyDelta(s0, snapshots[1]);
        assert(s1.hands["0"].length === 4, "snap1: P0 now has 4 cards (got ace)");
        assert(s1.hands["1"] === 2, "snap1: P1 lost a card (now 2)");
        assert(s1.lastAsk !== null, "snap1: lastAsk present");
        assert(s1.lastAsk.SEAT === 0, "snap1: asker is seat 0");
        assert(s1.lastAsk.TARGET === 1, "snap1: target is seat 1");
        assert(s1.lastAsk.RANK === 1, "snap1: asked for Aces");
        assert(s1.lastAsk.GOT === 1, "snap1: got 1 card");
        assert(s1.turn === 0, "snap1: turn stays (success)");

        // Snapshot 2: same state, player 1's view (hidden state differs)
        const s2 = gfApplyDelta(base, snapshots[2]);
        assert(typeof s2.hands["0"] === 'number', "snap2: P1 sees P0 hand as count");
        assert(s2.hands["0"] === 4, "snap2: P0 has 4 cards");
        assert(Array.isArray(s2.hands["1"]), "snap2: P1 sees own hand as array");
        assert(s2.hands["1"].length === 2, "snap2: P1 has 2 cards");
        assert(s2.lastAsk.GOT === 1, "snap2: same lastAsk for both players");

        // Snapshot 3: after Go Fish (player 0's view)
        const s3 = gfApplyDelta(s1, snapshots[3]);
        assert(s3.hands["0"].length === 5, "snap3: P0 drew a card (now 5)");
        assert(s3.deckCount === 1, "snap3: deck shrunk to 1");
        assert(s3.lastAsk.GOT === 0, "snap3: Go Fish (got 0)");
        assert(s3.lastAsk.RANK === 2, "snap3: asked for 2s");
        assert(s3.turn === 1, "snap3: turn passed to P1");

        // Snapshot 4: same Go Fish state, player 1's view
        const s4 = gfApplyDelta(base, snapshots[4]);
        assert(typeof s4.hands["0"] === 'number', "snap4: P1 sees P0 as count");
        assert(s4.hands["0"] === 5, "snap4: P0 has 5 cards");
        assert(Array.isArray(s4.hands["1"]), "snap4: P1 sees own hand");

        // Verify getMyHand works with real data
        const p0seat = getSeatForPlayer(s1, 0);
        const p0hand = getMyHand(s1, p0seat);
        assert(p0hand.length === 4, "snap1: getMyHand returns 4 cards for P0");
        assert(p0hand[0].RANK !== undefined, "snap1: cards have RANK");
        assert(p0hand[0].SUIT !== undefined, "snap1: cards have SUIT");

        // Verify sync works with real data
        const local = { tick: 0, status: 'WAITING', turn: 0, deckCount: 0, hands: {}, books: {}, lastAsk: null, players: {} };
        gfSync(local, s3);
        assert(local.lastAsk.GOT === 0, "sync'd lastAsk from real snapshot");
        assert(local.turn === 1, "sync'd turn from real snapshot");
    } else {
        console.log("  SKIP: gofish-snapshots.json not found (run Lisp dump first)");
    }
}

// --- Summary ---
console.log(`\n=== Go Fish Cross-Platform Results: ${pass} passed, ${fail} failed ===`);
if (fail > 0) process.exit(1);
