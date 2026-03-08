import * as fp from '../gateway/fixed-point.js';
import * as physics from '../gateway/physics.js';
import { bombermanUpdate } from '../gateway/bomberman/logic.js';

// Polyfill globals for deterministic testing
Object.assign(globalThis, fp);
Object.assign(globalThis, physics);

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
            [0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0],
            [0, 0, 0, 0, 0]
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
assert(p.x === 1010, "Player moved right by 10 (0.1 units)");
assert(p.y === 1000, "Player Y remained 1000");

// --- Test Case 1b: Full Speed Movement ---
console.log("\nTesting Full Speed Movement (JS)...");
const fullSpeedInputs = { "0": { dx: 1, dy: 0 } };
const s1b = bombermanUpdate(initialState, fullSpeedInputs);
const p1b = s1b.players["0"];
console.log(`Result: x=${p1b.x}, y=${p1b.y}`);
assert(p1b.x === 1100, "Player moved right by 100 (1 unit)");

// --- Test Case 2: Collision with Wall ---
console.log("\nTesting Collision with Wall (JS)...");
const wallState = JSON.parse(JSON.stringify(initialState));
wallState.customState.level[1][2] = 1; // Wall at x=2
const collisionInputs = {
    "0": { dx: 5.0, dy: 0 } 
};
const stateAfterCollision = bombermanUpdate(wallState, collisionInputs);
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
assert(p3.x === 1010, "Player allowed to move out of overlapping bomb");

    // --- Test Case 4: Bomb Planting ---
    console.log("\nTesting Bomb Planting (JS)...");
    const bombInputs = { "0": { "drop-bomb": true } };
    const stateAfterBomb = bombermanUpdate(initialState, bombInputs);
    const bombs = stateAfterBomb.customState.bombs;
    // (1000, 1000) -> (1000+500, 1000+500) -> (1500, 1500) -> floor(1.5, 1.5) -> "1,1"
    console.log("Bombs:", JSON.stringify(bombs));
    assert(bombs["1,1"] !== undefined, "Bomb planted at (1,1)");
    assert(bombs["1,1"].tm === 179, "Bomb timer initialized to 179 (180 - 1 tick)");

    console.log("\nAll JS Bomberman Cross-Platform Tests Passed!");
