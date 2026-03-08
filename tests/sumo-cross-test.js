import * as fp from '../gateway/fixed-point.js';
import { sumoUpdate, sumoJoin } from '../gateway/sumo/logic.js';

// Polyfill globals for deterministic testing
Object.assign(globalThis, fp);

function assert(condition, message) {
    if (!condition) {
        console.error("FAIL: " + message);
        process.exit(1);
    }
    console.log("PASS: " + message);
}

// --- Test Case 1: Simple Movement & Friction ---
console.log("
Testing Sumo Movement (JS)...");
const initialState = {
    tick: 0,
    players: {
        "0": { id: 0, x: 0, y: 0, vx: 0, vy: 0, h: 100 }
    },
    customState: {}
};

// Apply right input for 1 tick
const inputs = { "0": { dx: 1.0, dy: 0.0 } };
const s1 = sumoUpdate(initialState, inputs);
const p1 = s1.players["0"];

// ACCELERATION = 10, FRICTION = 950
// Expected vx = fpMul(1000, 10) = 10
// Expected x = 0 + 10 = 10
console.log(`Result s1: x=${p1.x}, vx=${p1.vx}`);
assert(p1.vx === 10, "vx increased by acceleration");
assert(p1.x === 10, "x increased by vx");

// Apply NO input for 1 tick (friction test)
const s2 = sumoUpdate(s1, {});
const p2 = s2.players["0"];
// Expected vx = fpMul(10, 950) = 9
// Expected x = 10 + 9 = 19
console.log(`Result s2: x=${p2.x}, vx=${p2.vx}`);
assert(p2.vx === 9, "vx decreased by friction");
assert(p2.x === 19, "x increased correctly with friction");

// --- Test Case 2: Boundary Check ---
console.log("
Testing Sumo Ring Boundary (JS)...");
const edgeState = {
    tick: 100,
    players: {
        "0": { id: 0, x: 9900, y: 0, vx: 200, vy: 0, h: 100 }
    }
};
const s3 = sumoUpdate(edgeState, {});
const p3 = s3.players["0"];
console.log(`Result s3: x=${p3.x}, h=${p3.h}`);
assert(p3.h === 0, "Player fell out of the ring");

// --- Test Case 3: Player Collision ---
console.log("
Testing Sumo Player Collision (JS)...");
const collisionState = {
    tick: 200,
    players: {
        "0": { id: 0, x: 0, y: 0, vx: 0, vy: 0, h: 100 },
        "1": { id: 1, x: 800, y: 0, vx: 0, vy: 0, h: 100 }
    }
};
const s4 = sumoUpdate(collisionState, {});
const p0_after = s4.players["0"];
console.log(`P0: x=${p0_after.x}, vx=${p0_after.vx}`);
assert(p0_after.vx === -5, "P0 vx set by collision force");
assert(p0_after.x === 0, "P0 position NOT updated yet (collision handled after movement)");

// --- Test Case 4: Random Spawn ---
console.log("
Testing Sumo Random Spawn (JS)...");
const newPlayer = sumoJoin(0, {});
console.log(`P0 Spawn: x=${newPlayer.x}, y=${newPlayer.y}`);
assert(newPlayer.x === 0 && newPlayer.y === 0, "Player spawned at 0,0 (client prediction wait)");

console.log("
All JS Sumo Cross-Platform Tests Passed!");
