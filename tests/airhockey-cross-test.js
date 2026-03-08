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

// 1. Join/Start sequence
const p0 = { id: 0, x: 0, y: -4000, vx: 0, vy: 0, sc: 0 };
const p1 = { id: 1, x: 0, y: 4000, vx: 0, vy: 0, sc: 0 };
const initialState = {
    tick: 0,
    players: { 0: p0, 1: p1 },
    puck: { x: 0, y: 0, vx: 0, vy: 0 },
    status: 'active'
};

// 2. Simple movement
const inputs = { 0: { tx: 500, ty: -4500 } };
const s1 = airhockeyUpdate(initialState, inputs);
console.log(`Result s1: p0.x=${s1.players[0].x}, p0.y=${s1.players[0].y}`);
assert(s1.players[0].x === 500, "Player 0 moved to target X");
assert(s1.players[0].y === -4500, "Player 0 moved to target Y");

// 3. Puck Physics (Friction)
const stateWithMovingPuck = {
    ...initialState,
    puck: { x: 0, y: 0, vx: 1000, vy: 0 }
};
const s2 = airhockeyUpdate(stateWithMovingPuck, {});
// Friction 0.99 (990). 1000 * 0.99 = 990. New X = 0 + 990 = 990.
console.log(`Result s2: puck.x=${s2.puck.x}, puck.vx=${s2.puck.vx}`);
assert(s2.puck.vx === 990, "Puck velocity decreased by friction");
assert(s2.puck.x === 990, "Puck position updated by velocity");

console.log("\nAll JS Air Hockey Cross-Platform Tests Passed!");
