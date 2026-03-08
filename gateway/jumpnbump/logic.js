/**
 * Jump and Bump logic ported to JavaScript for FoldBack.
 * Uses Fixed-Point math for determinism.
 */

import { fpToFloat, fbRandInt, fpFromFloat, fpAdd, fpMul, fpDiv, fpClamp, fpSub } from '../fixed-point.js';
import { fpAABBOverlapP } from '../physics.js';

const JNB_TILE_SIZE = 16000;
const JNB_PLAYER_SIZE = 16000;
const JNB_GRAVITY = 500;
const JNB_JUMP_FORCE = -6000; // Increased from -4270
const JNB_ACCELERATION = 250;
const JNB_FRICTION = 900;
const JNB_ICE_FRICTION = 995;
const JNB_MAX_SPEED = 1500;

const JNB_MAP = [
    [1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0],
    [1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1],
    [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1],
    [1, 1, 1, 0, 0, 1, 1, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 1],
    [1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1],
    [3, 3, 3, 3, 3, 3, 3, 3, 1, 1, 0, 0, 0, 0, 0, 1, 3, 3, 3, 1, 1, 1],
    [2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
];

export function getJnbTile(fpx, fpy) {
    const tx = Math.floor(fpToFloat(fpx) / 16);
    const ty = Math.floor(fpToFloat(fpy) / 16);
    if (isNaN(tx) || isNaN(ty) || tx < 0 || tx >= 22 || ty < 0 || ty >= 17) return 0;
    return JNB_MAP[ty][tx];
}

export function randomJnbSpawn(seed) {
    let tx, ty;
    let currentSeed = seed;
    while (true) {
        [currentSeed, tx] = fbRandInt(currentSeed, 22);
        [currentSeed, ty] = fbRandInt(currentSeed, 15); // Max ty=15
        const tile = JNB_MAP[ty][tx];
        const below = JNB_MAP[ty + 1][tx];
        if (tile === 0 && (below === 1 || below === 3)) {
            return [currentSeed, fpFromFloat(tx * 16), fpFromFloat(ty * 16)];
        }
    }
}

export function jnbUpdate(state, inputs) {
    let nextTick = state.tick + 1;
    let players = { ...state.players };
    let custom = { ...(state.customState || {}) };
    let seed = custom.seed || 123;
    let nextPlayers = {};

    for (let pid in players) {
        let p = { ...players[pid] };
        let input = (inputs && inputs[pid]) || {};

        if (p.vx === undefined) p.vx = 0;
        if (p.vy === undefined) p.vy = 0;
        if (p.d === undefined) p.d = 0;
        if (p.og === undefined) p.og = false;

        if (p.h <= 0) {
            let randX, randY, rDir;
            [seed, randX, randY] = randomJnbSpawn(seed);
            [seed, rDir] = fbRandInt(seed, 2);
            nextPlayers[pid] = { id: Number(pid), x: randX, y: randY, vx: 0, vy: 0, h: 100, d: rDir, og: false };
            continue;
        }

        let dx = input.dx || 0;
        let jump = input.jump;

        let currentTileBelow = getJnbTile(p.x, fpAdd(p.y, JNB_PLAYER_SIZE));
        let friction = (currentTileBelow === 3) ? JNB_ICE_FRICTION : JNB_FRICTION;

        p.vx = fpDiv(fpMul(p.vx, friction), 1000);
        if (dx !== 0) {
            p.d = dx > 0 ? 0 : 1;
            p.vx = fpClamp(fpAdd(p.vx, dx > 0 ? JNB_ACCELERATION : -JNB_ACCELERATION), -JNB_MAX_SPEED, JNB_MAX_SPEED);
        }

        p.vy = fpAdd(p.vy, JNB_GRAVITY);

        let nx = fpAdd(p.x, p.vx);
        let ny = fpAdd(p.y, p.vy);
        
        let bottomY = fpAdd(ny, JNB_PLAYER_SIZE);
        let belowLeft = getJnbTile(nx, bottomY);
        let belowRight = getJnbTile(fpAdd(nx, JNB_PLAYER_SIZE), bottomY);
        let isOnGround = (belowLeft === 1 || belowRight === 1 || belowLeft === 3 || belowRight === 3);

        if (jump && isOnGround) {
            p.vy = JNB_JUMP_FORCE;
            ny = fpAdd(p.y, p.vy);
            isOnGround = false;
        }

        if (p.vy > 0 && isOnGround) {
            ny = fpFromFloat(Math.floor(fpToFloat(bottomY) / 16) * 16);
            ny = fpSub(ny, JNB_PLAYER_SIZE);
            p.vy = 0;
        }

        let sideLeft = getJnbTile(nx, fpAdd(ny, fpDiv(JNB_PLAYER_SIZE, 2)));
        let sideRight = getJnbTile(fpAdd(nx, JNB_PLAYER_SIZE), fpAdd(ny, fpDiv(JNB_PLAYER_SIZE, 2)));

        if (sideLeft === 1 || sideLeft === 3) {
            nx = fpFromFloat((Math.floor(fpToFloat(nx) / 16) + 1) * 16);
            p.vx = 0;
        }
        if (sideRight === 1 || sideRight === 3) {
            nx = fpFromFloat(Math.floor(fpToFloat(fpAdd(nx, JNB_PLAYER_SIZE)) / 16) * 16);
            nx = fpSub(nx, JNB_PLAYER_SIZE);
            p.vx = 0;
        }

        if (nx < 0) nx = 0;
        if (nx > 336000) nx = 336000;

        p.x = nx;
        p.y = ny;
        p.og = isOnGround;
        nextPlayers[pid] = p;
    }

    for (let id1 in nextPlayers) {
        for (let id2 in nextPlayers) {
            if (id1 === id2) continue;
            let p1 = nextPlayers[id1];
            let p2 = nextPlayers[id2];

            if (p1.h > 0 && p2.h > 0) {
                if (fpAABBOverlapP(p1.x, p1.y, JNB_PLAYER_SIZE, JNB_PLAYER_SIZE,
                                   p2.x, p2.y, JNB_PLAYER_SIZE, JNB_PLAYER_SIZE)) {
                    if (p1.vy > 0 && p1.y < p2.y) {
                        nextPlayers[id2] = { ...p2, h: 0 };
                        nextPlayers[id1] = { ...p1, vy: JNB_JUMP_FORCE };
                    }
                }
            }
        }
    }

    return {
        tick: nextTick,
        players: nextPlayers,
        customState: { ...custom, seed: seed }
    };
}

export function jnbApplyDelta(baseState, delta) {
    const newState = JSON.parse(JSON.stringify(baseState));
    newState.tick = delta.t;
    if (delta.s !== undefined) newState.customState.seed = delta.s;
    if (delta.p) {
        delta.p.forEach(dp => {
            newState.players[dp.id] = {
                id: dp.id,
                x: dp.x,
                y: dp.y,
                vx: dp.vx,
                vy: dp.vy,
                h: dp.h,
                d: dp.d,
                og: dp.og === 1
            };
        });
    }
    return newState;
}

export function jnbSync(localState, serverState, myPlayerId) {
    for (let id in serverState.players) {
        const sp = serverState.players[id];
        const lp = localState.players[id];

        // Trigger blood if health drops to 0
        if (lp && lp.h > 0 && sp.h <= 0) {
            spawnBlood(fpToFloat(lp.x), fpToFloat(lp.y));
        }

        if (id != myPlayerId) {
            localState.players[id] = sp;
        } else {
            if (lp) {
                lp.h = sp.h;
                lp.d = sp.d;
                lp.og = sp.og;
            } else {
                localState.players[id] = sp;
            }
        }
    }
    for (let id in localState.players) {
        if (!serverState.players[id]) delete localState.players[id];
    }
    localState.customState.seed = serverState.customState.seed;
}

const COLORS = ["#3498db", "#e74c3c", "#2ecc71", "#f1c40f", "#9b59b6", "#1abc9c", "#e67e22"];

let backgroundImage = null;
let spritesheet = null;
let objectSheet = null;
let rabbitData = null;
let rabbitStates = null;
let objectData = null;

let particles = [];

export function spawnBlood(x, y) {
    for (let i = 0; i < 8; i++) {
        particles.push({
            x: x + 8,
            y: y + 8,
            vx: (Math.random() - 0.5) * 4,
            vy: (Math.random() - 1) * 4,
            life: 30 + Math.random() * 20,
            frame: 15 + Math.floor(Math.random() * 6) // Frames 15-20 in objects.json
        });
    }
}

export function jnbRender(ctx, canvas, localState, TILE_SIZE, msPerTick = 16.6) {
    if (!rabbitData || !rabbitStates || !objectData) return;

    ctx.imageSmoothingEnabled = false;
    if (!backgroundImage) {
        backgroundImage = new Image();
        backgroundImage.src = 'gfx/bg.gif';
    }
    if (!spritesheet) {
        spritesheet = new Image();
        spritesheet.src = 'gfx/rabbit.gif';
    }
    if (!objectSheet) {
        objectSheet = new Image();
        objectSheet.src = 'gfx/objects.gif';
    }

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    if (backgroundImage.complete) {
        ctx.drawImage(backgroundImage, 0, 0, canvas.width, canvas.height);
    }

    const tick = localState.tick;

    // Render Players
    for (let id in localState.players) {
        const p = localState.players[id];
        const isDead = p.h <= 0;
        if (isDead) continue;
        
        const px = fpToFloat(p.x);
        const py = fpToFloat(p.y);

        let stateName = "stand_r";
        if (!p.og) {
            stateName = p.d === 0 ? "jump_r" : "jump_l";
        } else if (Math.abs(p.vx) > 100) {
            stateName = p.d === 0 ? "walk_r" : "walk_l";
        } else {
            stateName = p.d === 0 ? "stand_r" : "stand_l";
        }

        let state = rabbitStates[stateName];
        let frameOffset = 0;

        if (Array.isArray(state)) {
            let totalDuration = state.reduce((acc, f) => acc + f[1], 0);
            let time = (tick * msPerTick) % totalDuration;
            let elapsed = 0;
            for (let f of state) {
                elapsed += f[1];
                if (time < elapsed) {
                    frameOffset = f[0];
                    break;
                }
            }
        } else {
            frameOffset = state;
        }

        const rabbitBaseFrame = (p.id % 4) * 18;
        const frameIndex = rabbitBaseFrame + frameOffset;
        const frame = rabbitData[frameIndex];

        if (spritesheet.complete && frame) {
            const [sx, sy] = frame.pos;
            const [sw, sh] = frame.dims;
            const [hx, hy] = frame.hotspot;
            ctx.drawImage(spritesheet, sx, sy, sw, sh, px + hx, py + hy, sw, sh);
        }
    }

    // Render Particles
    if (objectSheet.complete) {
        for (let i = particles.length - 1; i >= 0; i--) {
            let p = particles[i];
            p.x += p.vx;
            p.y += p.vy;
            p.vy += 0.2; // Particle gravity
            p.life--;
            if (p.life <= 0) {
                particles.splice(i, 1);
                continue;
            }

            let frame = objectData[p.frame];
            if (frame) {
                const [sx, sy] = frame.pos;
                const [sw, sh] = frame.dims;
                const [hx, hy] = frame.hotspot;
                ctx.drawImage(objectSheet, sx, sy, sw, sh, p.x + hx, p.y + hy, sw, sh);
            }
        }
    }
}

export async function loadJnbAssets() {
    console.log("Loading JNB assets...");
    try {
        const r1 = await fetch('gfx/rabbit.json');
        if (!r1.ok) throw new Error(`Failed to load rabbit.json: ${r1.status}`);
        rabbitData = await r1.json();
        
        const r2 = await fetch('gfx/rabbitStates.json');
        if (!r2.ok) throw new Error(`Failed to load rabbitStates.json: ${r2.status}`);
        rabbitStates = await r2.json();

        const r3 = await fetch('gfx/objects.json');
        if (!r3.ok) throw new Error(`Failed to load objects.json: ${r3.status}`);
        objectData = await r3.json();
        
        console.log("JNB assets loaded!");
    } catch (e) {
        console.error("Failed to load JNB assets:", e);
        // Fallback or rethrow
        throw e;
    }
}
