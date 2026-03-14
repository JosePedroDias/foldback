import { FoldBackWorld, processServerMessage } from '../foldback-engine.js';
import { bombermanUpdate, bombermanApplyDelta, bombermanSync, bombermanRender } from './logic.js';

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');
const TILE_SIZE = 20; 

const urlParams = new URLSearchParams(window.location.search);
const isAutoplay = urlParams.get('autoplay') === '1';
const protocol = urlParams.get('protocol') || 'webrtc';
if (isAutoplay) document.getElementById('autoplayMode').style.display = 'block';

const world = new FoldBackWorld("bomberman");
window.world = world;
let connection = { send: (data) => {}, isOpen: () => false };

function onMessage(data) {
    const res = processServerMessage(world, data, bombermanUpdate, bombermanApplyDelta, bombermanSync);
    
    if (res.type === 'abort') {
        alert("Game ID Mismatch!");
        return;
    }
    
    if (res.tick !== undefined) {
        const ahead = world.currentTick - res.tick;
        const pCount = Object.keys(world.localState.players).length;
        document.getElementById('netStats').innerText = 
            `[${protocol.toUpperCase()}] ID: ${world.myPlayerId} | Tick: ${res.tick} (+${ahead}) | RTT: ${world.rtt}ms | Rollbacks: ${world.totalRollbacks} | Players: ${pCount}`;
    }
}

function renderLoop() {
    bombermanRender(ctx, canvas, world.localState, TILE_SIZE, world.myPlayerId);
    requestAnimationFrame(renderLoop);
}
requestAnimationFrame(renderLoop);

const keys = new Set();
window.addEventListener('keydown', (e) => { keys.add(e.key.toLowerCase()); });
window.addEventListener('keyup', (e) => { keys.delete(e.key.toLowerCase()); });

function sendInput() {
    if (connection.isOpen() && world.myPlayerId !== null) {
        const serverTick = world.authoritativeState.tick;
        const lead = world.currentTick - serverTick;

        if (lead < world.maxLead) {
            let dx = 0, dy = 0, bomb = false;
            
            if (isAutoplay) {
                if (Math.random() < 0.05) dx = (Math.random() < 0.5 ? -1 : 1);
                if (Math.random() < 0.05) dy = (Math.random() < 0.5 ? -1 : 1);
                if (Math.random() < 0.01) bomb = true;
            } else {
                if (keys.has('arrowleft') || keys.has('a')) dx = -1;
                if (keys.has('arrowright') || keys.has('d')) dx = 1;
                if (keys.has('arrowup') || keys.has('w')) dy = -1;
                if (keys.has('arrowdown') || keys.has('s')) dy = 1;
                if (keys.has(' ') || keys.has('b')) bomb = true;
            }
            
            const nextTick = world.currentTick + 1;
            const input = { dx, dy, 'drop-bomb': bomb, t: nextTick };

            connection.send(JSON.stringify({ DX: dx, DY: dy, DROP_BOMB: bomb, TICK: nextTick }));
            
            if (!world.inputBuffer.has(nextTick)) world.inputBuffer.set(nextTick, {});
            world.inputBuffer.get(nextTick)[world.myPlayerId] = input;
            
            const inputsForTick = {};
            inputsForTick[world.myPlayerId] = input;
            
            world.localState = bombermanUpdate(world.localState, inputsForTick);
            world.currentTick = nextTick;
            world.history.set(nextTick, JSON.parse(JSON.stringify(world.localState)));
        }

        const now = Date.now();
        if (now - world.lastPingTime > 500) {
            const pingId = now;
            world.pings.set(pingId, now);
            connection.send(JSON.stringify({ TYPE: "PING", ID: pingId }));
            world.lastPingTime = now;
        }
    }
    setTimeout(sendInput, world.msPerTick);
}

// Notify server immediately on tab close/navigation
window.addEventListener('beforeunload', () => {
    if (connection.isOpen()) {
        connection.send(JSON.stringify({ TYPE: "LEAVE" }));
    }
});

function onOpen() {
    console.log(`${protocol} Open!`);
    connection.send(JSON.stringify({ TYPE: "JOIN" }));
    const joinRetry = setInterval(() => {
        if (world.myPlayerId !== null) { clearInterval(joinRetry); return; }
        if (connection.isOpen()) connection.send(JSON.stringify({ TYPE: "JOIN" }));
    }, 1000);
    sendInput();
}

async function connectWS() {
    const ws = new WebSocket(`ws://${window.location.host}/ws`);
    ws.onopen = onOpen;
    ws.onmessage = (e) => onMessage(e.data);
    connection = { send: (data) => ws.send(data), isOpen: () => ws.readyState === WebSocket.OPEN };
}

async function connectWebRTC() {
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

if (protocol === 'webrtc') connectWebRTC();
else connectWS();
