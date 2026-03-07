const { updateGame } = require('../gateway/foldback-engine.js');
const { bombermanUpdate } = require('../gateway/bomberman-logic.js');

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
        "0": { id: 0, x: 1.0, y: 1.0, h: 100 }
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
assert(Math.abs(p.x - 1.1) < 0.0001, "Player moved right to 1.1");
assert(p.y === 1.0, "Player Y remained 1.0");

// --- Test Case 2: Collision with Wall ---
console.log("\nTesting Collision with Wall (JS)...");
const collisionInputs = {
    "0": { dx: 0.5, dy: 0 } // Move from 1.0 to 1.5. Wall at x=2.
};

// Player x=1.0. dx=0.5 -> target 1.5.
// Offsets: +0.35 and -0.35.
// (1.5 + 0.35) = 1.85. 
// getTile(1.85) -> Math.floor(1.85 + 0.5) = Math.floor(2.35) = 2.
// Level is:
// [1, 1, 1, 1, 1]
// [1, 0, 0, 0, 1]  <- y=1
// [1, 1, 1, 1, 1]
// Row 1, Index 2 is 0 (floor). Index 3 is 0. Index 4 is 1 (Wall).
// Wait, my JS level was:
// level: [
//    [1, 1, 1, 1, 1],
//    [1, 0, 0, 0, 1],
//    [1, 1, 1, 1, 1]
// ]
// x=1 is 0. x=2 is 0. x=3 is 0. x=4 is 1.
// If I am at x=1.5, my right edge is 1.85. 
// getTile(1.85) -> ix = floor(1.85 + 0.5) = 2.
// level[1][2] is 0. SO IT SHOULD NOT COLLIDE.
// Ah! In Lisp test, where did I put the wall?
// (setf level (set-tile level 2 1 1))  <-- Wall at x=2 in Lisp!
// But in JS test, I had [1, 0, 0, 0, 1] for row 1. x=2 is 0.
const stateAfterCollision = bombermanUpdate(initialState, collisionInputs);
const p2 = stateAfterCollision.players["0"];
console.log(`Result: x=${p2.x}, y=${p2.y}`);
assert(p2.x === 1.0, "Player blocked by wall at x=2");

// --- Test Case 3: Passable-Until-Left Bomb ---
console.log("\nTesting Passable-Until-Left Bomb (JS)...");
const stateWithBomb = JSON.parse(JSON.stringify(initialState));
stateWithBomb.customState.bombs["1,1"] = { x: 1, y: 1, timer: 100 };
// Player is AT (1,1). Bomb is AT (1,1). Should be allowed to move.
const moveOutInputs = {
    "0": { dx: 0.1, dy: 0 }
};
const stateAfterBombMove = bombermanUpdate(stateWithBomb, moveOutInputs);
const p3 = stateAfterBombMove.players["0"];
console.log(`Result: x=${p3.x}, y=${p3.y}`);
assert(Math.abs(p3.x - 1.1) < 0.0001, "Player allowed to move out of overlapping bomb");

console.log("\nAll JS Cross-Platform Tests Passed!");
