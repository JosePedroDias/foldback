import { jnbUpdate, jnbApplyDelta } from '../gateway/jumpnbump/logic.js';

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
    if (p.h === 100 && p.x === 64000 && p.y === 160000 && p.d === 1 && state.customState.seed === 1668141782) {
        console.log("PASS: Deterministic respawn match");
    } else {
        console.log(`FAIL: Unexpected respawn values: x=${p.x}, y=${p.y}, d=${p.d}, seed=${state.customState.seed}`);
        process.exit(1);
    }
}

function testApplyDelta() {
    console.log("\nTesting Jump and Bump ApplyDelta with UPPERCASE keys (JS)...");

    const baseState = {
        tick: 0,
        players: {},
        customState: { seed: 0 }
    };

    const delta = {
        TICK: 42,
        SEED: 9999,
        PLAYERS: [
            { ID: 0, X: 64000, Y: 160000, VX: 250, VY: -500, HEALTH: 100, DIR: 0, ON_GROUND: 1, KILLS: 3 },
            { ID: 1, X: 128000, Y: 80000, VX: -100, VY: 500, HEALTH: 0, DIR: 1, ON_GROUND: 0, KILLS: 1 }
        ]
    };

    const result = jnbApplyDelta(baseState, delta);

    function assertEq(got, expected, label) {
        if (got === expected) {
            console.log(`  PASS: ${label} (${got} == ${expected})`);
        } else {
            console.log(`  FAIL: ${label} (got ${got}, expected ${expected})`);
            process.exit(1);
        }
    }

    assertEq(result.tick, 42, "ApplyDelta: tick");
    assertEq(result.customState.seed, 9999, "ApplyDelta: seed");
    assertEq(Object.keys(result.players).length, 2, "ApplyDelta: 2 players");

    const p0 = result.players[0];
    assertEq(p0.id, 0, "ApplyDelta: p0 id");
    assertEq(p0.x, 64000, "ApplyDelta: p0 x");
    assertEq(p0.y, 160000, "ApplyDelta: p0 y");
    assertEq(p0.vx, 250, "ApplyDelta: p0 vx");
    assertEq(p0.vy, -500, "ApplyDelta: p0 vy");
    assertEq(p0.h, 100, "ApplyDelta: p0 h");
    assertEq(p0.d, 0, "ApplyDelta: p0 d");
    assertEq(p0.og, true, "ApplyDelta: p0 og");
    assertEq(p0.k, 3, "ApplyDelta: p0 k");

    const p1 = result.players[1];
    assertEq(p1.h, 0, "ApplyDelta: p1 h (dead)");
    assertEq(p1.d, 1, "ApplyDelta: p1 d");
    assertEq(p1.og, false, "ApplyDelta: p1 og (airborne)");
    assertEq(p1.k, 1, "ApplyDelta: p1 k");
}

testGravity();
testSquish();
testRespawn();
testApplyDelta();
console.log("\nAll JS Jump and Bump Cross-Platform Tests Passed!");
