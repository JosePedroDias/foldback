import { createGameClient } from '../game-client.js';
import { jnbUpdate, jnbApplyDelta, jnbSync, jnbRender, loadJnbAssets, spawnBlood } from './logic.js';
import { fpToFloat } from '../fixed-point.js';

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');
const TILE_SIZE = 16;
canvas.width = 400;
canvas.height = 256;

const keys = new Set();
window.addEventListener('keydown', (e) => { keys.add(e.key.toLowerCase()); });
window.addEventListener('keyup', (e) => { keys.delete(e.key.toLowerCase()); });

// Sound Manager
const sounds = {};
function loadSound(name, url) {
    const audio = new Audio(url);
    sounds[name] = audio;
}
loadSound('jump', 'sfx/jump.ogg');
loadSound('pop', 'sfx/death.ogg');
loadSound('splash', 'sfx/splash.ogg');
loadSound('spring', 'sfx/spring.ogg');

function playSound(name) {
    if (sounds[name]) {
        sounds[name].currentTime = 0;
        sounds[name].play().catch(() => {});
    }
}

// Death detection — must run at simulation rate (per-tick), not render rate,
// because JNB respawns instantly (1 tick dead). Render can miss the transition.
const lastDeathTime = new Map();
function checkDeaths(before, after) {
    for (let id in after) {
        const bp = before[id];
        const ap = after[id];
        if (bp && ap && bp.h > 0 && ap.h <= 0) {
            const now = Date.now();
            if (now - (lastDeathTime.get(id) || 0) > 500) {
                lastDeathTime.set(id, now);
                spawnBlood(fpToFloat(bp.x), fpToFloat(bp.y));
                playSound('pop');
            }
        }
    }
}

function snapshotHealth(players) {
    const snap = {};
    for (let id in players) {
        const p = players[id];
        snap[id] = { h: p.h, x: p.x, y: p.y };
    }
    return snap;
}

let healthSnapshot = {};
let prevRenderState = new Map();

const { world } = createGameClient({
    gameName: 'jumpnbump',
    updateFn: jnbUpdate,
    applyDeltaFn: jnbApplyDelta,
    syncFn: jnbSync,
    render: () => jnbRender(ctx, canvas, world.localState, TILE_SIZE, world.msPerTick),
    getInput: (world) => {
        let dx = 0, jump = false;
        if (keys.has('a')) dx = -1;
        if (keys.has('d')) dx = 1;
        if (keys.has(' ') || keys.has('w')) jump = true;
        healthSnapshot = snapshotHealth(world.localState.players);
        return { local: { dx, jump }, wire: { DX: dx, JUMP: jump } };
    },
    onAfterInput: (world) => {
        checkDeaths(healthSnapshot, world.localState.players);
    },
    onBeforeMessage: (world) => {
        healthSnapshot = snapshotHealth(world.localState.players);
    },
    onAfterMessage: (world, res) => {
        if (res.tick !== undefined) {
            checkDeaths(healthSnapshot, world.localState.players);
        }
    },
    onRender: () => {
        for (let id in world.localState.players) {
            const p = world.localState.players[id];
            const prev = prevRenderState.get(id);
            if (prev && !p.og && prev.og && p.vy < -1000) playSound('jump');
            prevRenderState.set(id, { og: p.og });
        }
    },
    init: loadJnbAssets,
});
