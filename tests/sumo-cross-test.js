const { sumoUpdate } = require('../gateway/sumo-logic.js');

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
        "0": { id: 0, x: 0.0, y: 0.0, vx: 0.0, vy: 0.0, h: 100 }
    },
    customState: {}
};

// Apply right input for 1 tick
const inputs = { "0": { dx: 1.0, dy: 0.0 } };
const s1 = sumoUpdate(initialState, inputs);
const p1 = s1.players["0"];

// ACCELERATION = 0.015, FRICTION = 0.96
// Expected vx = 0.0 * 0.96 + 1.0 * 0.015 = 0.015
// Expected x = 0.0 + 0.015 = 0.015
console.log(`Result s1: x=${p1.x}, vx=${p1.vx}`);
assert(Math.abs(p1.vx - 0.015) < 0.0001, "vx increased by acceleration");
assert(Math.abs(p1.x - 0.015) < 0.0001, "x increased by vx");

// Apply NO input for 1 tick (friction test)
const s2 = sumoUpdate(s1, {});
const p2 = s2.players["0"];
// Expected vx = 0.015 * 0.96 + 0.0 = 0.0144
// Expected x = 0.015 + 0.0144 = 0.0294
console.log(`Result s2: x=${p2.x}, vx=${p2.vx}`);
assert(Math.abs(p2.vx - 0.0144) < 0.0001, "vx decreased by friction");
assert(Math.abs(p2.x - 0.0294) < 0.0001, "x increased correctly with friction");

// --- Test Case 2: Boundary Check ---
console.log("\nTesting Sumo Ring Boundary (JS)...");
const edgeState = {
    tick: 100,
    players: {
        "0": { id: 0, x: 9.9, y: 0.0, vx: 0.2, vy: 0.0, h: 100 }
    }
};
// Next tick: x = 9.9 + (0.2 * 0.96 + 0) = 9.9 + 0.192 = 10.092
// RING_RADIUS = 10.0. 10.092 > 10.0 -> h should become 0.
const s3 = sumoUpdate(edgeState, {});
const p3 = s3.players["0"];
console.log(`Result s3: x=${p3.x}, h=${p3.h}`);
assert(p3.h === 0, "Player fell out of the ring");

console.log("\nAll JS Sumo Cross-Platform Tests Passed!");
