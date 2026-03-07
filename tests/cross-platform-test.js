const fp = require('../gateway/fixed-point.js');
const physics = require('../gateway/physics.js');
const { bombermanUpdate } = require('../gateway/bomberman-logic.js');

// Polyfill globals for deterministic testing
Object.assign(global, fp);
Object.assign(global, physics);

function assert(condition, message) {
    if (!condition) {
        console.error("FAIL: " + message);
        process.exit(1);
    }
    console.log("PASS: " + message);
}

// --- Test Case 1: Simple Movement ---
console.log("\nTesting Simple Movement (JS)...");
const initialState = {
    tick: 0,
    players: {
        "0": { id: 0, x: 1000, y: 1000, h: 100 }
    },
    customState: {
        level: [
            [1, 1, 1, 1, 1],
            [1, 0, 1, 0, 1],
            [1, 1, 1, 1, 1]
        ],
        bombs: {},
        explosions: [],
        bots: []
    }
};

const inputs = {
    "0": { dx: 0.1, dy: 0 }
};

const nextState = bombermanUpdate(initialState, inputs);
const p = nextState.players["0"];
console.log(`Result: x=${p.x}, y=${p.y}`);
assert(p.x === 1100, "Player moved right to 1100");
assert(p.y === 1000, "Player Y remained 1000");

// --- Test Case 2: Collision with Wall ---
console.log("\nTesting Collision with Wall (JS)...");
const collisionInputs = {
    "0": { dx: 0.5, dy: 0 } 
};
const stateAfterCollision = bombermanUpdate(initialState, collisionInputs);
const p2 = stateAfterCollision.players["0"];
console.log(`Result: x=${p2.x}, y=${p2.y}`);
assert(p2.x === 1000, "Player blocked by wall at x=2000");

// --- Test Case 3: Passable-Until-Left Bomb ---
console.log("\nTesting Passable-Until-Left Bomb (JS)...");
const stateWithBomb = JSON.parse(JSON.stringify(initialState));
stateWithBomb.customState.bombs["1,1"] = { x: 1, y: 1, tm: 100 };
const moveOutInputs = {
    "0": { dx: 0.1, dy: 0 }
};
const stateAfterBombMove = bombermanUpdate(stateWithBomb, moveOutInputs);
const p3 = stateAfterBombMove.players["0"];
console.log(`Result: x=${p3.x}, y=${p3.y}`);
assert(p3.x === 1100, "Player allowed to move out of overlapping bomb");

console.log("\nAll JS Bomberman Cross-Platform Tests Passed!");
