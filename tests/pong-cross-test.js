import * as fp from '../gateway/fixed-point.js';
import { pongUpdate } from '../gateway/pong/logic.js';

Object.assign(globalThis, fp);

function assert(condition, message) {
    if (!condition) {
        console.error("FAIL: " + message);
        process.exit(1);
    }
    console.log("PASS: " + message);
}

console.log("\nTesting Pong Cross-Platform (JS)...");

// --- Shared initial state ---
const p0 = { id: 0, side: 0, x: -5500, y: 0, sc: 0 };
const p1 = { id: 1, side: 1, x: 5500, y: 0, sc: 0 };
const initialState = {
    tick: 0,
    players: { 0: p0, 1: p1 },
    ball: { x: 0, y: 0, vx: 80, vy: 0 },
    status: 'active'
};

// --- Test 1: Paddle movement ---
const s1 = pongUpdate(initialState, { 0: { ty: 1000 } });
console.log(`  p0.y=${s1.players[0].y}`);
assert(s1.players[0].y === 1000, "Player 0 moved to target Y");

// --- Test 2: Paddle clamped to table ---
const s2 = pongUpdate(initialState, { 0: { ty: 5000 } });
console.log(`  p0.y clamped=${s2.players[0].y}`);
assert(s2.players[0].y === 3250, "Player 0 clamped to max Y (4000 - 750 = 3250)");

// --- Test 3: Ball moves each tick ---
const s3 = pongUpdate(initialState, {});
console.log(`  ball.x=${s3.ball.x}, ball.vx=${s3.ball.vx}`);
assert(s3.ball.x === 80, "Ball moved right by vx=80");
assert(s3.ball.vx === 80, "Ball vx unchanged (no friction)");

// --- Test 4: Ball bounces off top wall ---
const sTop = {
    ...initialState,
    ball: { x: 0, y: 3800, vx: 80, vy: 100 }
};
const s4 = pongUpdate(sTop, {});
console.log(`  ball after top bounce: y=${s4.ball.y}, vy=${s4.ball.vy}`);
assert(s4.ball.y === 3850, "Ball y clamped to 4000 - 150 = 3850");
assert(s4.ball.vy === -100, "Ball vy reversed after top wall bounce");

// --- Test 5: Ball bounces off bottom wall ---
const sBot = {
    ...initialState,
    ball: { x: 0, y: -3800, vx: 80, vy: -100 }
};
const s5 = pongUpdate(sBot, {});
console.log(`  ball after bottom bounce: y=${s5.ball.y}, vy=${s5.ball.vy}`);
assert(s5.ball.y === -3850, "Ball y clamped to -(4000 - 150) = -3850");
assert(s5.ball.vy === 100, "Ball vy reversed after bottom wall bounce");

// --- Test 6: Left paddle hit (center) ---
// Ball approaching left paddle, paddle at y=0
const sHitL = {
    tick: 0,
    players: { 0: { ...p0, y: 0 }, 1: p1 },
    ball: { x: -5400, y: 0, vx: -80, vy: 0 },
    status: 'active'
};
const s6 = pongUpdate(sHitL, {});
console.log(`  left paddle hit: bx=${s6.ball.x}, bvx=${s6.ball.vx}, bvy=${s6.ball.vy}`);
// Ball at x=-5480, which is: bx - 150 = -5630 <= -5500 AND bx=-5480 >= -5500
assert(s6.ball.vx === 80, "Ball vx reversed after left paddle hit");
assert(s6.ball.vy === 0, "Ball vy is 0 (hit center of paddle)");
assert(s6.ball.x === -5350, "Ball pushed out to paddle edge + radius");

// --- Test 7: Right paddle hit (off-center) ---
// Ball hits right paddle at relative position 0.5 (375 out of 750)
const sHitR = {
    tick: 0,
    players: { 0: p0, 1: { ...p1, y: 0 } },
    ball: { x: 5400, y: 375, vx: 80, vy: 0 },
    status: 'active'
};
const s7 = pongUpdate(sHitR, {});
console.log(`  right paddle hit: bx=${s7.ball.x}, bvx=${s7.ball.vx}, bvy=${s7.ball.vy}`);
assert(s7.ball.vx === -80, "Ball vx reversed after right paddle hit");
// relY = fpDiv(375, 750) = 500, bvy = fpMul(500, 120) = 60
assert(s7.ball.vy === 60, "Ball vy = 60 (half paddle = half max vy)");
assert(s7.ball.x === 5350, "Ball pushed out to paddle edge - radius");

// --- Test 8: Ball exits left — Player 1 scores ---
const sGoalL = {
    tick: 0,
    players: {
        0: { ...p0, y: 2000, sc: 3 },
        1: { ...p1, sc: 5 }
    },
    ball: { x: -5950, y: 0, vx: -80, vy: 0 },
    status: 'active'
};
const s8 = pongUpdate(sGoalL, {});
console.log(`  goal left: p1.sc=${s8.players[1].sc}, ball=(${s8.ball.x},${s8.ball.y}), status=${s8.status}`);
assert(s8.players[1].sc === 6, "Player 1 score incremented to 6");
assert(s8.ball.x === 0 && s8.ball.y === 0, "Ball reset to center");
assert(s8.ball.vx === -80, "Ball serves left (toward P0 who missed)");
assert(s8.players[0].y === 0, "Player 0 paddle reset to center");

// --- Test 9: Ball exits right — Player 0 scores ---
const sGoalR = {
    tick: 0,
    players: {
        0: { ...p0, sc: 0 },
        1: { ...p1, y: 2000, sc: 0 }
    },
    ball: { x: 5950, y: 0, vx: 80, vy: 0 },
    status: 'active'
};
const s9 = pongUpdate(sGoalR, {});
console.log(`  goal right: p0.sc=${s9.players[0].sc}, ball=(${s9.ball.x},${s9.ball.y})`);
assert(s9.players[0].sc === 1, "Player 0 score incremented to 1");
assert(s9.ball.x === 0 && s9.ball.y === 0, "Ball reset to center");
assert(s9.ball.vx === 80, "Ball serves right (toward P1 who missed)");

// --- Test 10: Win condition ---
const sWin = {
    tick: 0,
    players: {
        0: { ...p0, sc: 10 },
        1: { ...p1, y: 2000, sc: 7 }
    },
    ball: { x: 5950, y: 0, vx: 80, vy: 0 },
    status: 'active'
};
const s10 = pongUpdate(sWin, {});
console.log(`  win: p0.sc=${s10.players[0].sc}, status=${s10.status}`);
assert(s10.players[0].sc === 11, "Player 0 reaches 11");
assert(s10.status === 'p0-wins', "Status is p0-wins");

// --- Test 11: Game activates with 2 players ---
const sWaiting = {
    tick: 0,
    players: { 0: p0 },
    ball: null,
    status: 'waiting'
};
const s11a = pongUpdate(sWaiting, {});
assert(s11a.status === 'waiting', "Still waiting with 1 player");

const sReady = {
    tick: 0,
    players: { 0: p0, 1: p1 },
    ball: null,
    status: 'waiting'
};
const s11b = pongUpdate(sReady, {});
assert(s11b.status === 'active', "Active with 2 players");
assert(s11b.ball !== null, "Ball created when game activates");
assert(s11b.ball.vx === 80, "Ball starts moving right");

console.log("\nAll JS Pong Cross-Platform Tests Passed!");
