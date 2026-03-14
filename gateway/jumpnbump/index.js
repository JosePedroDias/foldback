import { FoldBackWorld, processServerMessage } from '../foldback-engine.js';
import { jnbUpdate, jnbApplyDelta, jnbSync, jnbRender, loadJnbAssets, spawnBlood } from './logic.js';
import { fpToFloat } from '../fixed-point.js';

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');
const TILE_SIZE = 16;

const urlParams = new URLSearchParams(window.location.search);
const protocol = urlParams.get('protocol') || 'webrtc';

const world = new FoldBackWorld("jumpnbump");
const keys = new Set();
let connection = { send: (data) => {}, isOpen: () => false };

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
        sounds[name].play().catch(() => {}); // Ignore user-gesture errors
    }
}

// Death detection — must run at simulation rate (per-tick), not render rate,
// because JNB respawns instantly (1 tick dead). Render can miss the transition.
const lastDeathTime = new Map(); // pid -> Date.now() when blood last spawned
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

function onMessage(data) {
    const before = snapshotHealth(world.localState.players);
    const res = processServerMessage(world, data, jnbUpdate, jnbApplyDelta, jnbSync);

    if (res.type === 'abort') {
        alert("Game ID Mismatch!");
        return;
    }

    if (res.tick !== undefined) {
        checkDeaths(before, world.localState.players);
        const ahead = world.currentTick - res.tick;
        const pCount = Object.keys(world.localState.players).length;
        document.getElementById('netStats').innerText =
            `[${protocol.toUpperCase()}] ID: ${world.myPlayerId} | Tick: ${res.tick} (+${ahead}) | RTT: ${world.rtt}ms | Rollbacks: ${world.totalRollbacks} | Players: ${pCount}`;
    }
}

async function init() {
    console.log("Initializing Jump and Bump...");
    try {
        await loadJnbAssets();
        console.log("Assets loaded, connecting...");
        if (protocol === 'webrtc') connectWebRTC();
        else connectWS();
        requestAnimationFrame(gameLoop);
    } catch (e) {
        console.error("Initialization failed:", e);
    }
}

let prevRenderState = new Map(); // for jump sounds (og transition lasts many ticks, safe in render)

function tick() {
    if (connection.isOpen() && world.myPlayerId !== null) {
        // Limit how far we can get ahead of the server authoritative state
        const serverTick = world.authoritativeState.tick;
        if (world.currentTick - serverTick < world.maxLead) {
            let dx = 0, jump = false;
            if (keys.has('a')) dx = -1;
            if (keys.has('d')) dx = 1;
            if (keys.has(' ') || keys.has('w')) jump = true;

            const nextTick = world.currentTick + 1;
            const inputsForTick = {};

            const input = { dx, jump, t: nextTick };
            connection.send(`(:dx ${dx} :jump ${jump ? "t" : "nil"} :t ${nextTick})`);

            inputsForTick[world.myPlayerId] = input;
            if (!world.inputBuffer.has(nextTick)) world.inputBuffer.set(nextTick, {});
            world.inputBuffer.get(nextTick)[world.myPlayerId] = input;

            const beforePrediction = snapshotHealth(world.localState.players);
            world.localState = jnbUpdate(world.localState, inputsForTick);
            checkDeaths(beforePrediction, world.localState.players);
            world.currentTick = nextTick;
            world.history.set(nextTick, JSON.parse(JSON.stringify(world.localState)));
        }

        const now = Date.now();
        if (now - world.lastPingTime > 500) {
            const pingId = now;
            world.pings.set(pingId, now);
            connection.send(`(:ping ${pingId})`);
            world.lastPingTime = now;
        }
    }
}

let lastFrameTime = 0;
let tickAccumulator = 0;

function gameLoop(now) {
    if (lastFrameTime > 0) {
        tickAccumulator = Math.min(tickAccumulator + (now - lastFrameTime), world.msPerTick * 10);
    }
    lastFrameTime = now;

    while (tickAccumulator >= world.msPerTick) {
        tick();
        tickAccumulator -= world.msPerTick;
    }

    for (let id in world.localState.players) {
        const p = world.localState.players[id];
        const prev = prevRenderState.get(id);
        if (prev && !p.og && prev.og && p.vy < -1000) playSound('jump');
        prevRenderState.set(id, { og: p.og });
    }
    jnbRender(ctx, canvas, world.localState, TILE_SIZE, world.msPerTick);
    requestAnimationFrame(gameLoop);
}

function onOpen() {
    console.log("Connection Open!");
    connection.send("()");
    const joinRetry = setInterval(() => {
        if (world.myPlayerId !== null) { clearInterval(joinRetry); return; }
        if (connection.isOpen()) connection.send("()");
    }, 1000);
}

async function connectWS() {
    const url = `ws://${window.location.host}/ws`;
    console.log("Connecting to WS:", url);
    const ws = new WebSocket(url);
    ws.onopen = onOpen;
    ws.onmessage = (e) => onMessage(e.data);
    connection = { send: (data) => ws.send(data), isOpen: () => ws.readyState === WebSocket.OPEN };
}

async function connectWebRTC() {
    console.log("Connecting to WebRTC...");
    const pc = new RTCPeerConnection({ iceServers: [{ urls: `stun:${window.location.hostname}:3478` }] });
    const dc = pc.createDataChannel("foldback", { ordered: false, maxRetransmits: 0 });
    dc.onopen = onOpen;
    dc.onmessage = (e) => onMessage(e.data);
    connection = { send: (data) => dc.send(data), isOpen: () => dc.readyState === "open" };
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await new Promise(resolve => {
        if (pc.iceGatheringState === 'complete') return resolve();
        const timeout = setTimeout(resolve, 2000);
        pc.onicegatheringstatechange = () => {
            if (pc.iceGatheringState === 'complete') { clearTimeout(timeout); resolve(); }
        };
    });
    const response = await fetch('/offer', { method: 'POST', body: JSON.stringify(pc.localDescription) });
    const answer = await response.json();
    await pc.setRemoteDescription(answer);
}

window.addEventListener('keydown', (e) => { keys.add(e.key.toLowerCase()); });
window.addEventListener('keyup', (e) => { keys.delete(e.key.toLowerCase()); });

canvas.width = 400; 
canvas.height = 256;

init();
