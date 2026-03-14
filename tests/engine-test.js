/**
 * Engine Reconciliation Tests
 *
 * Tests processServerMessage, rollback, structural change detection,
 * and the full client-side prediction/reconciliation flow.
 * Uses pong as the game under test.
 */

import { FoldBackWorld, processServerMessage } from '../gateway/foldback-engine.js';
import { pongUpdate, pongApplyDelta, pongSync } from '../gateway/pong/logic.js';

function assert(condition, message) {
    if (!condition) {
        console.error("FAIL: " + message);
        process.exit(1);
    }
    console.log("PASS: " + message);
}

// --- Helpers ---

function makeDelta(tick, status, players, ball, winTick) {
    const d = { TICK: tick, STATUS: status };
    if (ball) d.BALL = { X: ball.x, Y: ball.y, VX: ball.vx, VY: ball.vy };
    if (winTick !== undefined) d.WIN_TICK = winTick;
    if (players) {
        d.PLAYERS = players.map(p => ({
            ID: p.id, SIDE: p.side, X: p.x, Y: p.y, SCORE: p.sc || 0
        }));
    }
    return d;
}

function feed(world, delta) {
    return processServerMessage(world, JSON.stringify(delta), pongUpdate, pongApplyDelta, pongSync);
}

function makeWelcome(id, gameId) {
    return { YOUR_ID: id, GAME_ID: gameId || 'pong', TICK_RATE: 60 };
}

const P0 = { id: 0, side: 0, x: -5500, y: 0, sc: 0 };
const P1 = { id: 1, side: 1, x: 5500, y: 0, sc: 0 };
const BALL0 = { x: 0, y: 0, vx: 80, vy: 0 };

// Simulate what sendInput does: one tick of client-side prediction
function clientPredict(world, myInput) {
    const nextTick = world.currentTick + 1;
    const inputsForTick = {};
    inputsForTick[world.myPlayerId] = myInput;

    if (!world.inputBuffer.has(nextTick)) world.inputBuffer.set(nextTick, {});
    world.inputBuffer.get(nextTick)[world.myPlayerId] = myInput;

    world.localState = pongUpdate(world.localState, inputsForTick);
    world.currentTick = nextTick;
    world.history.set(nextTick, JSON.parse(JSON.stringify(world.localState)));
}


console.log("Testing Engine Reconciliation...\n");

// --- Test 1: Welcome ---
{
    const w = new FoldBackWorld('pong');
    const res = feed(w, makeWelcome(0));
    assert(res.type === 'welcome', "Welcome: type is welcome");
    assert(w.myPlayerId === 0, "Welcome: myPlayerId set to 0");
    assert(w.tickRate === 60, "Welcome: tickRate set");
    assert(w.msPerTick === 1000 / 60, "Welcome: msPerTick calculated");
}

// --- Test 2: Game ID mismatch aborts ---
{
    const w = new FoldBackWorld('pong');
    const res = feed(w, { YOUR_ID: 0, GAME_ID: 'airhockey', TICK_RATE: 60 });
    assert(res.type === 'abort', "Mismatch: returns abort");
}

// --- Test 3: First tick triggers initial sync ---
{
    const w = new FoldBackWorld('pong');
    feed(w, makeWelcome(0));
    const res = feed(w, makeDelta(1, 'WAITING', [P0], null));
    assert(res.type === 'tick', "First tick: type is tick");
    assert(w.localState.tick === 1, "First tick: localState.tick synced");
    assert(w.currentTick === 1, "First tick: currentTick synced");
    assert(w.authoritativeState.tick === 1, "First tick: authoritativeState updated");
    assert(Object.keys(w.localState.players).length === 1, "First tick: 1 player in localState");
}

// --- Test 4: Normal tick updates authoritative state ---
{
    const w = new FoldBackWorld('pong');
    feed(w, makeWelcome(0));
    feed(w, makeDelta(1, 'WAITING', [P0], null));
    feed(w, makeDelta(2, 'WAITING', [P0], null));
    assert(w.authoritativeState.tick === 2, "Normal tick: auth tick updated to 2");
}

// --- Test 5: Structural change (player count) triggers rollback ---
{
    const w = new FoldBackWorld('pong');
    w.reconciliationThresholdSq = 1;
    feed(w, makeWelcome(0));
    // Tick 1: 1 player, WAITING
    feed(w, makeDelta(1, 'WAITING', [P0], null));
    // Client predicts ticks 2-5 (all 1 player WAITING since not ACTIVE)
    // Manually populate predictions to simulate what would happen
    for (let t = 2; t <= 5; t++) {
        const prev = w.history.get(t - 1);
        const next = pongUpdate(prev, {});
        w.history.set(t, next);
        w.currentTick = t;
    }
    // Verify predictions have 1 player
    assert(Object.keys(w.history.get(5).players).length === 1, "Structural: predicted 1 player at tick 5");

    const rollbacksBefore = w.totalRollbacks;
    // Server says tick 5 has 2 players ACTIVE
    feed(w, makeDelta(5, 'ACTIVE', [P0, P1], BALL0));
    assert(w.totalRollbacks === rollbacksBefore + 1, "Structural: rollback triggered on player count change");
    assert(Object.keys(w.localState.players).length === 2, "Structural: localState now has 2 players");
    assert(w.localState.status === 'ACTIVE', "Structural: localState status is ACTIVE");
}

// --- Test 6: Status change triggers rollback ---
{
    const w = new FoldBackWorld('pong');
    w.reconciliationThresholdSq = 1;
    feed(w, makeWelcome(0));
    feed(w, makeDelta(1, 'WAITING', [P0, P1], null));
    // Predict tick 2 with WAITING (before server transitions)
    const prev = w.history.get(1);
    // Force a WAITING prediction with 2 players
    const predicted = { ...prev, tick: 2 };
    w.history.set(2, predicted);
    w.currentTick = 2;

    const rollbacksBefore = w.totalRollbacks;
    // Server says tick 2 is ACTIVE
    feed(w, makeDelta(2, 'ACTIVE', [P0, P1], BALL0));
    assert(w.totalRollbacks === rollbacksBefore + 1, "Status change: rollback triggered");
    assert(w.localState.status === 'ACTIVE', "Status change: localState is ACTIVE");
}

// --- Test 7: Position mismatch triggers rollback ---
{
    const w = new FoldBackWorld('pong');
    w.reconciliationThresholdSq = 1; // 1 unit squared threshold
    feed(w, makeWelcome(0));
    // Initial sync with ACTIVE state
    feed(w, makeDelta(1, 'ACTIVE', [P0, P1], BALL0));
    // Predict tick 2 with player 0 at y=2000 (moved)
    clientPredict(w, { ty: 2000 });
    assert(w.currentTick === 2, "Position: predicted to tick 2");

    const rollbacksBefore = w.totalRollbacks;
    // Server says tick 2 has player 0 still at y=0 (different from our y=2000)
    feed(w, makeDelta(2, 'ACTIVE', [P0, P1], { x: 80, y: 0, vx: 80, vy: 0 }));
    assert(w.totalRollbacks === rollbacksBefore + 1, "Position: rollback triggered on y mismatch");
}

// --- Test 8: Position match does NOT trigger rollback ---
{
    const w = new FoldBackWorld('pong');
    w.reconciliationThresholdSq = 1;
    feed(w, makeWelcome(0));
    feed(w, makeDelta(1, 'ACTIVE', [P0, P1], BALL0));
    // Predict tick 2 with y=0 (no movement, matches server)
    clientPredict(w, { ty: 0 });

    const rollbacksBefore = w.totalRollbacks;
    // Server also says y=0 — should match
    feed(w, makeDelta(2, 'ACTIVE', [P0, P1], { x: 80, y: 0, vx: 80, vy: 0 }));
    assert(w.totalRollbacks === rollbacksBefore, "No rollback: positions match");
    // Foundation fix: history at tick 2 should be authoritative
    const h2 = w.history.get(2);
    assert(h2.tick === 2, "Foundation fix: history updated at tick 2");
}

// --- Test 9: Sync copies remote player, preserves local position ---
{
    const w = new FoldBackWorld('pong');
    w.reconciliationThresholdSq = 1;
    feed(w, makeWelcome(0));
    feed(w, makeDelta(1, 'ACTIVE', [P0, P1], BALL0));
    // Predict with local player at y=1500
    clientPredict(w, { ty: 1500 });

    // Server: remote player moved to y=500, local player at y=0 (mismatch but we care about sync)
    const p0Server = { ...P0, y: 0 };
    const p1Server = { ...P1, y: 500 };
    feed(w, makeDelta(2, 'ACTIVE', [p0Server, p1Server], { x: 160, y: 0, vx: 80, vy: 0 }));

    // After sync: remote player (1) should be at server position
    assert(w.localState.players[1].y === 500, "Sync: remote player y updated to 500");
    // Local player score should be synced from server
    assert(w.localState.players[0].sc === 0, "Sync: local player score synced");
}

// --- Test 10: Sync removes departed player ---
{
    const w = new FoldBackWorld('pong');
    w.reconciliationThresholdSq = 1;
    feed(w, makeWelcome(0));
    feed(w, makeDelta(1, 'ACTIVE', [P0, P1], BALL0));
    assert(Object.keys(w.localState.players).length === 2, "Before leave: 2 players");

    // Server now has only 1 player (player 1 left, reset to WAITING)
    feed(w, makeDelta(2, 'WAITING', [{ ...P0, sc: 0, y: 0 }], null));
    assert(Object.keys(w.localState.players).length === 1, "After leave: 1 player");
    assert(w.localState.players[1] === undefined, "After leave: player 1 gone");
    assert(w.localState.status === 'WAITING', "After leave: status is WAITING");
}

// --- Test 11: Jump forward when far behind ---
{
    const w = new FoldBackWorld('pong');
    feed(w, makeWelcome(0));
    feed(w, makeDelta(1, 'WAITING', [P0], null));
    assert(w.currentTick === 1, "Jump: starts at tick 1");

    // Server jumps far ahead
    feed(w, makeDelta(100, 'WAITING', [P0], null));
    assert(w.currentTick === 100, "Jump: currentTick jumped to 100");
    assert(w.localState.tick === 100, "Jump: localState.tick jumped to 100");
}

// --- Test 12: History cleanup ---
{
    const w = new FoldBackWorld('pong');
    w.reconciliationThresholdSq = 1;
    feed(w, makeWelcome(0));
    // Feed 130 ticks to trigger cleanup
    for (let t = 1; t <= 130; t++) {
        feed(w, makeDelta(t, 'WAITING', [P0], null));
    }
    assert(w.history.size <= 121, "Cleanup: history pruned (size=" + w.history.size + ")");
    // Feed one more and verify no crash
    const res = feed(w, makeDelta(131, 'WAITING', [P0], null));
    assert(res.type === 'tick', "Cleanup: still works after pruning");
}

// --- Test 13: Full prediction + reconciliation cycle ---
{
    const w = new FoldBackWorld('pong');
    w.reconciliationThresholdSq = 1;
    feed(w, makeWelcome(0));
    feed(w, makeDelta(1, 'ACTIVE', [P0, P1], BALL0));
    // Client predicts 3 ticks ahead
    clientPredict(w, { ty: 500 });
    clientPredict(w, { ty: 1000 });
    clientPredict(w, { ty: 1500 });
    assert(w.currentTick === 4, "Cycle: predicted to tick 4");

    // Server confirms tick 2 with matching position
    feed(w, makeDelta(2, 'ACTIVE',
        [{ ...P0, y: 500 }, P1],
        { x: 160, y: 0, vx: 80, vy: 0 }));
    assert(w.totalRollbacks === 0, "Cycle: no rollback when server matches");

    // Server confirms tick 3 with DIFFERENT position (misprediction)
    const rollbacksBefore = w.totalRollbacks;
    feed(w, makeDelta(3, 'ACTIVE',
        [{ ...P0, y: 800 }, P1],
        { x: 240, y: 0, vx: 80, vy: 0 }));
    assert(w.totalRollbacks === rollbacksBefore + 1, "Cycle: rollback on misprediction at tick 3");
    // After rollback+resim, localState should be at currentTick (4) with corrected history
    assert(w.localState.tick === 4, "Cycle: localState still at tick 4 after rollback");
    assert(w.currentTick === 4, "Cycle: currentTick still 4");
}

// --- Test 14: Pong response ---
{
    const w = new FoldBackWorld('pong');
    feed(w, makeWelcome(0));
    const pingId = 12345;
    w.pings.set(pingId, Date.now() - 50); // simulate 50ms ago
    const res = feed(w, { PONG: pingId });
    assert(res.type === 'pong', "Pong: type is pong");
    assert(w.rtt >= 40 && w.rtt <= 200, "Pong: RTT is reasonable (" + w.rtt + "ms)");
    assert(w.maxLead >= 2, "Pong: maxLead calculated");
}

// --- Test 15: Missing tick returns error ---
{
    const w = new FoldBackWorld('pong');
    feed(w, makeWelcome(0));
    const res = feed(w, { foo: "bar" });
    assert(res.type === 'error', "Error: missing tick returns error");
}

// --- Test 16: WAITING → ACTIVE → player leaves → WAITING cycle ---
{
    const w = new FoldBackWorld('pong');
    w.reconciliationThresholdSq = 1;
    feed(w, makeWelcome(0));

    // Phase 1: alone, WAITING
    feed(w, makeDelta(1, 'WAITING', [P0], null));
    assert(w.localState.status === 'WAITING', "Lifecycle: starts WAITING");
    assert(Object.keys(w.localState.players).length === 1, "Lifecycle: 1 player");

    // Phase 2: 2nd player joins, ACTIVE
    feed(w, makeDelta(2, 'ACTIVE', [P0, P1], BALL0));
    assert(w.localState.status === 'ACTIVE', "Lifecycle: now ACTIVE");
    assert(Object.keys(w.localState.players).length === 2, "Lifecycle: 2 players");
    assert(w.localState.ball !== null, "Lifecycle: ball exists");

    // Phase 3: predict a couple ticks while active
    clientPredict(w, { ty: 200 });
    clientPredict(w, { ty: 400 });

    // Phase 4: 2nd player leaves
    feed(w, makeDelta(5, 'WAITING', [{ ...P0, y: 0, sc: 0 }], null));
    assert(w.localState.status === 'WAITING', "Lifecycle: back to WAITING");
    assert(Object.keys(w.localState.players).length === 1, "Lifecycle: 1 player after leave");
    assert(w.localState.ball === null, "Lifecycle: ball removed");

    // Phase 5: new player joins, ACTIVE again
    const P2 = { id: 2, side: 1, x: 5500, y: 0, sc: 0 };
    feed(w, makeDelta(6, 'ACTIVE', [P0, P2], BALL0));
    assert(w.localState.status === 'ACTIVE', "Lifecycle: ACTIVE again with new player");
    assert(Object.keys(w.localState.players).length === 2, "Lifecycle: 2 players again");
}

console.log("\nAll Engine Reconciliation Tests Passed!");
