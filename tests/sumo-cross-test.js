const fp = require('../gateway/fixed-point.js');
const { sumoUpdate } = require('../gateway/sumo-logic.js');

// Polyfill globals for deterministic testing
Object.assign(global, fp);

function assert(condition, message) {
    if (!condition) {
        console.error("FAIL: " + message);
        process.exit(1);
    }
    console.log("PASS: " + message);
}

// --- Test Case 1: Simple Movement & Friction ---
console.log("\nTesting Sumo Movement (JS)...");
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

// ACCELERATION = 15, FRICTION = 960
// Expected vx = fpAdd(fpMul(0, 960), fpMul(1000, 15)) = 15
// Expected x = 0 + 15 = 15
console.log(`Result s1: x=${p1.x}, vx=${p1.vx}`);
assert(p1.vx === 15, "vx increased by acceleration");
assert(p1.x === 15, "x increased by vx");

// Apply NO input for 1 tick (friction test)
const s2 = sumoUpdate(s1, {});
const p2 = s2.players["0"];
// Expected vx = fpMul(15, 960) = 14
// Expected x = 15 + 14 = 29
console.log(`Result s2: x=${p2.x}, vx=${p2.vx}`);
assert(p2.vx === 14, "vx decreased by friction");
assert(p2.x === 29, "x increased correctly with friction");

// --- Test Case 2: Boundary Check ---
console.log("\nTesting Sumo Ring Boundary (JS)...");
const edgeState = {
    tick: 100,
    players: {
        "0": { id: 0, x: 9900, y: 0, vx: 200, vy: 0, h: 100 }
    }
};
// RING_RADIUS = 10000. nx = 9900 + fpMul(200, 960) = 9900 + 192 = 10092 > 10000.
const s3 = sumoUpdate(edgeState, {});
const p3 = s3.players["0"];
console.log(`Result s3: x=${p3.x}, h=${p3.h}`);
assert(p3.h === 0, "Player fell out of the ring");

console.log("\nAll JS Sumo Cross-Platform Tests Passed!");
