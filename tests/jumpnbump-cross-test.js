const { jnbUpdate } = require('../gateway/jumpnbump-logic.js');

function testGravity() {
    console.log("Testing Jump and Bump Gravity (JS)...");
    let state = { tick: 0, players: { 0: { id: 0, x: 100000, y: 0, vx: 0, vy: 0, h: 100 } } };
    
    state = jnbUpdate(state, {});
    let p = state.players[0];
    
    console.log(`Result: y=${p.y}, vy=${p.vy}`);
    if (p.vy > 0 && p.y > 0) {
        console.log("PASS: Gravity applied");
    } else {
        console.log("FAIL: Gravity not applied");
        process.exit(1);
    }
}

function testSquish() {
    console.log("\nTesting Jump and Bump Squish (JS)...");
    // P1 falling onto P2. P2 is at y=100000. P1 is at y=90000. Player size is 16000.
    // They are 10000 units apart, which is less than 16000, so they overlap.
    let state = { 
        tick: 0, 
        players: { 
            0: { id: 0, x: 100000, y: 90000, vx: 0, vy: 1000, h: 100 },
            1: { id: 1, x: 100000, y: 100000, vx: 0, vy: 0, h: 100 }
        } 
    };
    
    state = jnbUpdate(state, {});
    let p1 = state.players[0];
    let p2 = state.players[1];
    
    console.log(`P1: y=${p1.y}, vy=${p1.vy} | P2: h=${p2.h}`);
    if (p2.h === 0 && p1.vy < 0) {
        console.log("PASS: P1 squished P2 and bounced");
    } else {
        console.log("FAIL: Squish logic failed");
        process.exit(1);
    }
}

function testRespawn() {
    console.log("\nTesting Jump and Bump Respawn Determinism (JS)...");
    let state = { 
        tick: 0, 
        players: { 
            0: { id: 0, x: 100000, y: 100000, vx: 0, vy: 0, h: 0 } 
        },
        customState: { seed: 123 }
    };
    
    state = jnbUpdate(state, {});
    let p = state.players[0];
    
    console.log(`P0 Respawn: x=${p.x}, y=${p.y}, d=${p.d}, seed=${state.customState.seed}`);
    // Expected values from seed 123
    if (p.h === 100 && p.x === 64000 && p.y === 160000 && p.d === 1 && state.customState.seed === 1668141782) {
        console.log("PASS: Deterministic respawn match");
    } else {
        console.log(`FAIL: Unexpected respawn values: x=${p.x}, y=${p.y}, d=${p.d}, seed=${state.customState.seed}`);
        process.exit(1);
    }
}

testGravity();
testSquish();
testRespawn();
console.log("\nAll JS Jump and Bump Cross-Platform Tests Passed!");
