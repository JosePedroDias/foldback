import * as fp from '../gateway/fixed-point.js';
import { airhockeyUpdate } from '../gateway/airhockey/logic.js';

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
const p0 = { id: 0, x: 0, y: -4000, vx: 0, vy: 0, sc: 0 };
const p1 = { id: 1, x: 0, y: 4000, vx: 0, vy: 0, sc: 0 };
const initialState = {
    tick: 0,
    players: { 0: p0, 1: p1 },
    puck: { x: 0, y: 0, vx: 0, vy: 0 },
    status: 'active'
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
        0: { id: 0, x: 0, y: -1000, vx: 0, vy: 0, sc: 0 },
        1: { ...p1 }
    },
    puck: { x: 0, y: -300, vx: 0, vy: 0 },
    status: 'active'
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
    status: 'active'
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
    status: 'active'
};
const s5 = airhockeyUpdate(sGoalTop, {});
console.log(`  goal-top: p1.sc=${s5.players[1].sc}, puck=(${s5.puck.x},${s5.puck.y}), status=${s5.status}`);
assert(s5.players[1].sc === 6, "Player 1 score incremented to 6");
assert(s5.puck.x === 0 && s5.puck.y === 0, "Puck reset to center after goal");
assert(s5.players[0].y === -4000, "Player 0 reset to own half after goal");
assert(s5.players[1].y === 4000, "Player 1 reset to own half after goal");
assert(s5.status === 'active', "Game still active (not a winning goal)");

// --- Test 6: Goal scoring (bottom — Player 0 scores) ---
const sGoalBot = {
    tick: 0,
    players: {
        0: { ...p0, sc: 0 },
        1: { ...p1, sc: 0 }
    },
    puck: { x: 0, y: 5800, vx: 0, vy: 300 },
    status: 'active'
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
    status: 'active'
};
const s7win = airhockeyUpdate(sWin, {});
console.log(`  win: p1.sc=${s7win.players[1].sc}, status=${s7win.status}`);
assert(s7win.players[1].sc === 11, "Player 1 score reaches 11");
assert(s7win.status === 'p1-wins', "Status is p1-wins");

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
    status: 'waiting'
};
const s9a = airhockeyUpdate(sWaiting, {});
assert(s9a.status === 'waiting', "Still waiting with 1 player");
assert(s9a.puck === null, "No puck with 1 player");

const sReady = {
    tick: 0,
    players: { 0: p0, 1: p1 },
    puck: null,
    status: 'waiting'
};
const s9b = airhockeyUpdate(sReady, {});
assert(s9b.status === 'active', "Active with 2 players");
assert(s9b.puck !== null, "Puck created when game activates");
assert(s9b.puck.x === 0 && s9b.puck.y === 0, "Puck starts at center");

console.log("\nAll JS Air Hockey Cross-Platform Tests Passed!");
