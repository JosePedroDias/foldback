import * as fp from '../gateway/fixed-point.js';
import { pongUpdate, pongApplyDelta, pongSync } from '../gateway/pong/logic.js';

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
    status: 'ACTIVE'
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
    status: 'ACTIVE'
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
    status: 'ACTIVE'
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
    status: 'ACTIVE'
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
    status: 'ACTIVE'
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
    status: 'ACTIVE'
};
const s10 = pongUpdate(sWin, {});
console.log(`  win: p0.sc=${s10.players[0].sc}, status=${s10.status}`);
assert(s10.players[0].sc === 11, "Player 0 reaches 11");
assert(s10.status === 'P0_WINS', "Status is P0_WINS");

// --- Test 11: Game activates with 2 players ---
const sWaiting = {
    tick: 0,
    players: { 0: p0 },
    ball: null,
    status: 'WAITING'
};
const s11a = pongUpdate(sWaiting, {});
assert(s11a.status === 'WAITING', "Still waiting with 1 player");

const sReady = {
    tick: 0,
    players: { 0: p0, 1: p1 },
    ball: null,
    status: 'WAITING'
};
const s11b = pongUpdate(sReady, {});
assert(s11b.status === 'ACTIVE', "Active with 2 players");
assert(s11b.ball !== null, "Ball created when game activates");
assert(s11b.ball.vx === 80, "Ball starts moving right");

// --- Test 12: Player leaves active game → full reset ---
const sLeave = {
    tick: 100,
    players: { 0: { ...p0, sc: 5, y: 2000 } },
    ball: { x: 1000, y: 500, vx: 80, vy: 40 },
    status: 'ACTIVE'
};
const s12 = pongUpdate(sLeave, {});
assert(s12.status === 'WAITING', "Status resets to WAITING when player leaves");
assert(s12.ball === null, "Ball removed on player leave");
assert(s12.players[0].sc === 0, "Score reset to 0 on player leave");
assert(s12.players[0].y === 0, "Paddle reset to center on player leave");

// --- Test 13: Win state stores winTick ---
const sWin13 = pongUpdate(sWin, {});
assert(sWin13.status === 'P0_WINS', "Status is P0_WINS");
assert(sWin13.winTick === 1, "winTick is set to the tick of the win");

// --- Test 14: Win state freezes until timer expires ---
const sFrozen = { ...sWin13, tick: 100 };
const s14 = pongUpdate(sFrozen, {});
assert(s14.status === 'P0_WINS', "Still P0_WINS before timer expires");
assert(s14.tick === 101, "Tick advances during win state");

// --- Test 15: Win state resets after 600 ticks ---
const sExpired = { ...sWin13, tick: 601 };
const s15 = pongUpdate(sExpired, {});
assert(s15.status === 'WAITING', "Status resets to WAITING after 10s");
assert(s15.ball === null, "Ball removed after win reset");
assert(s15.players[0].sc === 0, "Score reset after win timer");
assert(s15.players[0].y === 0, "Paddle reset after win timer");

// --- Test 16: pongApplyDelta with 2 players (wire format round-trip) ---
const serverDelta2P = {
    TICK: 50,
    STATUS: 'ACTIVE',
    BALL: { X: 1000, Y: -500, VX: 80, VY: 40 },
    PLAYERS: [
        { ID: 0, SIDE: 0, X: -5500, Y: 200, SCORE: 3 },
        { ID: 1, SIDE: 1, X: 5500, Y: -100, SCORE: 5 }
    ]
};
const baseEmpty = { tick: 0, players: {}, ball: null, status: 'WAITING' };
const applied = pongApplyDelta(baseEmpty, serverDelta2P);
assert(applied.tick === 50, "ApplyDelta: tick set");
assert(applied.status === 'ACTIVE', "ApplyDelta: status set");
assert(Object.keys(applied.players).length === 2, "ApplyDelta: 2 players present");
assert(applied.players[0].id === 0, "ApplyDelta: player 0 id");
assert(applied.players[0].side === 0, "ApplyDelta: player 0 side");
assert(applied.players[0].y === 200, "ApplyDelta: player 0 y");
assert(applied.players[0].sc === 3, "ApplyDelta: player 0 score mapped to sc");
assert(applied.players[1].id === 1, "ApplyDelta: player 1 id");
assert(applied.players[1].side === 1, "ApplyDelta: player 1 side");
assert(applied.players[1].y === -100, "ApplyDelta: player 1 y");
assert(applied.players[1].sc === 5, "ApplyDelta: player 1 score mapped to sc");
assert(applied.ball.x === 1000, "ApplyDelta: ball x");
assert(applied.ball.vy === 40, "ApplyDelta: ball vy");

// --- Test 17: pongApplyDelta with 1 player (before 2nd joins) ---
const serverDelta1P = {
    TICK: 10,
    STATUS: 'WAITING',
    PLAYERS: [
        { ID: 0, SIDE: 0, X: -5500, Y: 0, SCORE: 0 }
    ]
};
const applied1P = pongApplyDelta(baseEmpty, serverDelta1P);
assert(Object.keys(applied1P.players).length === 1, "ApplyDelta 1P: only 1 player");
assert(applied1P.ball === null, "ApplyDelta 1P: no ball");
assert(applied1P.status === 'WAITING', "ApplyDelta 1P: waiting");

// --- Test 18: pongSync merges new remote player into local state ---
const localBefore = {
    tick: 50, status: 'ACTIVE',
    players: { 0: { id: 0, side: 0, x: -5500, y: 300, sc: 2 } },
    ball: { x: 0, y: 0, vx: 80, vy: 0 }
};
const serverWith2 = {
    tick: 50, status: 'ACTIVE',
    players: {
        0: { id: 0, side: 0, x: -5500, y: 200, sc: 3 },
        1: { id: 1, side: 1, x: 5500, y: -100, sc: 5 }
    },
    ball: { x: 1000, y: -500, vx: 80, vy: 40 }
};
pongSync(localBefore, serverWith2, 0);
assert(Object.keys(localBefore.players).length === 2, "Sync: 2 players in local state after sync");
assert(localBefore.players[1] !== undefined, "Sync: player 1 exists in local state");
assert(localBefore.players[1].side === 1, "Sync: player 1 side correct");
assert(localBefore.players[1].y === -100, "Sync: player 1 y from server");
assert(localBefore.players[0].y === 300, "Sync: own player y NOT overwritten");
assert(localBefore.players[0].sc === 3, "Sync: own player score updated from server");

// --- Test 19: pongSync removes player that left ---
const localWith2 = {
    tick: 60, status: 'WAITING',
    players: {
        0: { id: 0, side: 0, x: -5500, y: 0, sc: 0 },
        1: { id: 1, side: 1, x: 5500, y: 0, sc: 0 }
    },
    ball: null
};
const serverWith1 = {
    tick: 60, status: 'WAITING',
    players: { 0: { id: 0, side: 0, x: -5500, y: 0, sc: 0 } },
    ball: null
};
pongSync(localWith2, serverWith1, 0);
assert(Object.keys(localWith2.players).length === 1, "Sync: player removed after leave");
assert(localWith2.players[1] === undefined, "Sync: player 1 gone");

// --- Test 20: pongApplyDelta then pongUpdate produces valid 2-player state ---
const stateFrom2PDelta = pongApplyDelta(baseEmpty, serverDelta2P);
const updated2P = pongUpdate(stateFrom2PDelta, { 0: { ty: 500 }, 1: { ty: -300 } });
assert(Object.keys(updated2P.players).length === 2, "Update after ApplyDelta: still 2 players");
assert(updated2P.players[0].y === 500, "Update after ApplyDelta: p0 moved");
assert(updated2P.players[1].y === -300, "Update after ApplyDelta: p1 moved");
assert(updated2P.ball !== null, "Update after ApplyDelta: ball exists");

console.log("\nAll JS Pong Cross-Platform Tests Passed!");
