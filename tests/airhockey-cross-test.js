import * as fp from '../gateway/fixed-point.js';
import { airhockeyUpdate, airhockeyApplyDelta, airhockeySync } from '../gateway/airhockey/logic.js';

// Polyfill globals for deterministic testing
Object.assign(globalThis, fp);

function assert(condition, message) {
    if (!condition) {
        console.error("FAIL: " + message);
        process.exit(1);
    }
    console.log("PASS: " + message);
}

console.log("\nTesting Air Hockey Cross-Platform (JS)...");

// --- Shared initial state ---
const p0 = { id: 0, side: 0, x: 0, y: -4000, vx: 0, vy: 0, sc: 0 };
const p1 = { id: 1, side: 1, x: 0, y: 4000, vx: 0, vy: 0, sc: 0 };
const initialState = {
    tick: 0,
    players: { 0: p0, 1: p1 },
    puck: { x: 0, y: 0, vx: 0, vy: 0 },
    status: 'ACTIVE'
};

// --- Test 1: Simple paddle movement ---
const s1 = airhockeyUpdate(initialState, { 0: { tx: 500, ty: -4500 } });
console.log(`  p0.x=${s1.players[0].x}, p0.y=${s1.players[0].y}`);
assert(s1.players[0].x === 500, "Player 0 moved to target X");
assert(s1.players[0].y === -4500, "Player 0 moved to target Y");

// --- Test 2: Puck friction ---
const sMoving = { ...initialState, puck: { x: 0, y: 0, vx: 1000, vy: 0 } };
const s2 = airhockeyUpdate(sMoving, {});
console.log(`  puck.x=${s2.puck.x}, puck.vx=${s2.puck.vx}`);
assert(s2.puck.vx === 990, "Puck velocity decreased by friction");
assert(s2.puck.x === 990, "Puck position updated by velocity");

// --- Test 3: Paddle-puck collision ---
// Paddle 0 at (0, -1000) moves to (0, -300) — overlaps with puck at (0, -300).
// Paddle radius=400, puck radius=300. They collide, puck is pushed away.
const sCollision = {
    tick: 0,
    players: {
        0: { id: 0, side: 0, x: 0, y: -1000, vx: 0, vy: 0, sc: 0 },
        1: { ...p1 }
    },
    puck: { x: 0, y: -300, vx: 0, vy: 0 },
    status: 'ACTIVE'
};
const s3 = airhockeyUpdate(sCollision, { 0: { tx: 0, ty: -300 } });
console.log(`  puck after collision: x=${s3.puck.x}, y=${s3.puck.y}, vx=${s3.puck.vx}, vy=${s3.puck.vy}`);
// Puck should be pushed upward (positive y direction away from paddle)
assert(s3.puck.y > 0, "Puck pushed away from paddle (y > 0)");
assert(s3.puck.vy > 0, "Puck gained positive vy from paddle hit");
// Exact values for cross-platform check
assert(s3.puck.x === 0, "Puck stays on x=0 (head-on collision)");
assert(s3.puck.y === 300, "Puck y after collision = 300");
assert(s3.puck.vy === 650, "Puck vy after collision = 650");

// --- Test 4: Wall bounce ---
// Puck near right wall moving rightward at moderate speed.
const sWall = {
    tick: 0,
    players: { 0: p0, 1: p1 },
    puck: { x: 3500, y: 0, vx: 300, vy: 0 },
    status: 'ACTIVE'
};
const s4 = airhockeyUpdate(sWall, {});
console.log(`  puck after wall bounce: x=${s4.puck.x}, vx=${s4.puck.vx}`);
// Puck should bounce back (negative vx) after hitting the right wall
assert(s4.puck.vx < 0, "Puck vx is negative after wall bounce");
assert(s4.puck.x === 3699, "Puck x after wall bounce = 3699");
assert(s4.puck.vx === -242, "Puck vx after wall bounce = -242");

// --- Test 5: Goal scoring (top — Player 1 scores) ---
// Puck at y=-5800 moving up toward top goal at y=-6000. Puck radius 300.
// After friction: vy = -297. New y = -6097. Within 300 of goal line -> goal-top triggers.
const sGoalTop = {
    tick: 0,
    players: {
        0: { ...p0, sc: 2 },
        1: { ...p1, sc: 5 }
    },
    puck: { x: 0, y: -5800, vx: 0, vy: -300 },
    status: 'ACTIVE'
};
const s5 = airhockeyUpdate(sGoalTop, {});
console.log(`  goal-top: p1.sc=${s5.players[1].sc}, puck=(${s5.puck.x},${s5.puck.y}), status=${s5.status}`);
assert(s5.players[1].sc === 6, "Player 1 score incremented to 6");
assert(s5.puck.x === 0 && s5.puck.y === 0, "Puck reset to center after goal");
assert(s5.players[0].y === -4000, "Player 0 reset to own half after goal");
assert(s5.players[1].y === 4000, "Player 1 reset to own half after goal");
assert(s5.status === 'ACTIVE', "Game still active (not a winning goal)");

// --- Test 6: Goal scoring (bottom — Player 0 scores) ---
const sGoalBot = {
    tick: 0,
    players: {
        0: { ...p0, sc: 0 },
        1: { ...p1, sc: 0 }
    },
    puck: { x: 0, y: 5800, vx: 0, vy: 300 },
    status: 'ACTIVE'
};
const s6goal = airhockeyUpdate(sGoalBot, {});
console.log(`  goal-bottom: p0.sc=${s6goal.players[0].sc}, puck=(${s6goal.puck.x},${s6goal.puck.y})`);
assert(s6goal.players[0].sc === 1, "Player 0 score incremented to 1");
assert(s6goal.puck.x === 0 && s6goal.puck.y === 0, "Puck reset to center after bottom goal");

// --- Test 7: Win condition (Player 1 reaches 11) ---
const sWin = {
    tick: 0,
    players: {
        0: { ...p0, sc: 3 },
        1: { ...p1, sc: 10 }
    },
    puck: { x: 0, y: -5800, vx: 0, vy: -300 },
    status: 'ACTIVE'
};
const s7win = airhockeyUpdate(sWin, {});
console.log(`  win: p1.sc=${s7win.players[1].sc}, status=${s7win.status}`);
assert(s7win.players[1].sc === 11, "Player 1 score reaches 11");
assert(s7win.status === 'P1_WINS', "Status is p1-wins");

// --- Test 8: Paddle clamped to own half ---
// Player 0 tries to move past center line (y > -paddle_radius).
const s8 = airhockeyUpdate(initialState, { 0: { tx: 0, ty: 1000 } });
console.log(`  p0 clamped: y=${s8.players[0].y}`);
assert(s8.players[0].y === -400, "Player 0 clamped to own half (y = -paddle_radius)");

// --- Test 9: Game activates when 2 players join ---
const sWaiting = {
    tick: 0,
    players: { 0: p0 },
    puck: null,
    status: 'WAITING'
};
const s9a = airhockeyUpdate(sWaiting, {});
assert(s9a.status === 'WAITING', "Still waiting with 1 player");
assert(s9a.puck === null, "No puck with 1 player");

const sReady = {
    tick: 0,
    players: { 0: p0, 1: p1 },
    puck: null,
    status: 'WAITING'
};
const s9b = airhockeyUpdate(sReady, {});
assert(s9b.status === 'ACTIVE', "Active with 2 players");
assert(s9b.puck !== null, "Puck created when game activates");
assert(s9b.puck.x === 0 && s9b.puck.y === 0, "Puck starts at center");

// --- Test 10: airhockeyApplyDelta with UPPERCASE JSON ---
const serverDelta = {
    TICK: 50,
    STATUS: 'ACTIVE',
    PUCK: { X: 1000, Y: -500, VX: 200, VY: 100 },
    PLAYERS: [
        { ID: 0, SIDE: 0, X: 500, Y: -4000, VX: 10, VY: 20, SCORE: 3 },
        { ID: 1, SIDE: 1, X: -200, Y: 4500, VX: -5, VY: 15, SCORE: 5 }
    ]
};
const baseEmpty = { tick: 0, players: {}, puck: null, status: 'WAITING' };
const applied = airhockeyApplyDelta(baseEmpty, serverDelta);
assert(applied.tick === 50, "ApplyDelta: tick set");
assert(applied.status === 'ACTIVE', "ApplyDelta: status set");
assert(Object.keys(applied.players).length === 2, "ApplyDelta: 2 players");
assert(applied.players[0].id === 0, "ApplyDelta: p0 id");
assert(applied.players[0].side === 0, "ApplyDelta: p0 side");
assert(applied.players[0].x === 500, "ApplyDelta: p0 x");
assert(applied.players[0].y === -4000, "ApplyDelta: p0 y");
assert(applied.players[0].vx === 10, "ApplyDelta: p0 vx");
assert(applied.players[0].sc === 3, "ApplyDelta: p0 score mapped to sc");
assert(applied.players[1].sc === 5, "ApplyDelta: p1 score mapped to sc");
assert(applied.puck.x === 1000, "ApplyDelta: puck x");
assert(applied.puck.vy === 100, "ApplyDelta: puck vy");

// --- Test 11: airhockeyApplyDelta with 1 player, no puck ---
const serverDelta1P = {
    TICK: 10,
    STATUS: 'WAITING',
    PLAYERS: [
        { ID: 0, SIDE: 0, X: 0, Y: -4000, VX: 0, VY: 0, SCORE: 0 }
    ]
};
const applied1P = airhockeyApplyDelta(baseEmpty, serverDelta1P);
assert(Object.keys(applied1P.players).length === 1, "ApplyDelta 1P: 1 player");
assert(applied1P.puck === null, "ApplyDelta 1P: no puck");
assert(applied1P.status === 'WAITING', "ApplyDelta 1P: WAITING");

// --- Test 12: airhockeySync merges remote player, preserves local position ---
const localBefore = {
    tick: 50, status: 'ACTIVE',
    players: { 0: { id: 0, side: 0, x: 500, y: -3000, vx: 0, vy: 0, sc: 2 } },
    puck: { x: 100, y: 200, vx: 50, vy: -30 }
};
const serverWith2 = {
    tick: 50, status: 'ACTIVE',
    players: {
        0: { id: 0, side: 0, x: 400, y: -3500, vx: 0, vy: 0, sc: 3 },
        1: { id: 1, side: 1, x: -200, y: 4500, vx: 0, vy: 0, sc: 5 }
    },
    puck: { x: 1000, y: -500, vx: 200, vy: 100 }
};
airhockeySync(localBefore, serverWith2, 0);
assert(Object.keys(localBefore.players).length === 2, "Sync: 2 players after sync");
assert(localBefore.players[1].y === 4500, "Sync: remote player y from server");
assert(localBefore.players[0].x === 500, "Sync: own player x NOT overwritten");
assert(localBefore.players[0].y === -3000, "Sync: own player y NOT overwritten");
assert(localBefore.players[0].sc === 3, "Sync: own player score updated from server");
// Puck should NOT be overwritten (predicted locally)
assert(localBefore.puck.x === 100, "Sync: puck x NOT overwritten (predicted)");

// --- Test 13: Update after ApplyDelta produces valid state ---
const stateFromDelta = airhockeyApplyDelta(baseEmpty, serverDelta);
const updatedState = airhockeyUpdate(stateFromDelta, { 0: { tx: 600, ty: -4200 }, 1: { tx: -100, ty: 4300 } });
assert(Object.keys(updatedState.players).length === 2, "Update after ApplyDelta: 2 players");
assert(updatedState.players[0].x === 600, "Update after ApplyDelta: p0 moved");
assert(updatedState.puck !== null, "Update after ApplyDelta: puck exists");

console.log("\nAll JS Air Hockey Cross-Platform Tests Passed!");
