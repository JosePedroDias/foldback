import { FoldBackWorld, processServerMessage } from '../foldback-engine.js';
import { jnbUpdate, jnbApplyDelta, jnbSync, jnbRender, loadJnbAssets } from './logic.js';

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

let lastStates = new Map(); // pid -> { h, og } for sound triggers

function onMessage(data) {
    const res = processServerMessage(world, data, jnbUpdate, jnbApplyDelta, jnbSync);
    
    if (res.type === 'abort') {
        alert("Game ID Mismatch!");
        return;
    }
    
    if (res.tick !== undefined) {
        const ahead = world.currentTick - res.tick;
        const pCount = Object.keys(world.localState.players).length;
        document.getElementById('netStats').innerText = 
            `[${protocol.toUpperCase()}] ID: ${world.myPlayerId} | Tick: ${res.tick} (+${ahead}) | RTT: ${world.rtt}ms | Rollbacks: ${world.totalRollbacks} | Players: ${pCount}`;

        // Sound Triggers
        for (let id in world.localState.players) {
            const p = world.localState.players[id];
            const last = lastStates.get(id);
            if (last) {
                if (p.h <= 0 && last.h > 0) playSound('pop');
                if (!p.og && last.og && p.vy < -1000) playSound('jump');
            }
            lastStates.set(id, { h: p.h, og: p.og });
        }
    }
}

async function init() {
    console.log("Initializing Jump and Bump...");
    try {
        await loadJnbAssets();
        console.log("Assets loaded, connecting...");
        if (protocol === 'webrtc') connectWebRTC();
        else connectWS();
        requestAnimationFrame(render);
    } catch (e) {
        console.error("Initialization failed:", e);
    }
}

function render() {
    jnbRender(ctx, canvas, world.localState, TILE_SIZE, world.msPerTick);
    requestAnimationFrame(render);
}

function sendInput() {
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
            
            world.localState = jnbUpdate(world.localState, inputsForTick);
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
    setTimeout(sendInput, world.msPerTick);
}

function onOpen() {
    console.log("Connection Open!");
    connection.send("()");
    const joinRetry = setInterval(() => {
        if (world.myPlayerId !== null) { clearInterval(joinRetry); return; }
        if (connection.isOpen()) connection.send("()");
    }, 1000);
    sendInput();
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
