import { FoldBackWorld, processServerMessage } from '../foldback-engine.js';
import { fpRound } from '../fixed-point.js';
import { airhockeyUpdate, airhockeyApplyDelta, airhockeySync, airhockeyRender } from './logic.js';

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

// Test state for Playwright
window.foldback_test_state = {
    clientState: null,
    serverState: null,
    lastInputSent: null,
    lastRollback: null,
    totalRollbacks: 0,
};

// Resize canvas to fit window
function resize() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
}
window.addEventListener('resize', resize);
resize();

const urlParams = new URLSearchParams(window.location.search);
const protocol = urlParams.get('protocol') || 'webrtc';

const world = new FoldBackWorld("airhockey");
window.world = world;
world.reconciliationThresholdSq = 1; // Any integer difference in FP triggers rollback
let connection = { send: (data) => {}, isOpen: () => false };
let mouseX = 0, mouseY = 0;

function onMessage(data) {
    const res = processServerMessage(world, data, airhockeyUpdate, airhockeyApplyDelta, airhockeySync);
    
    // Update test state
    window.foldback_test_state.serverState = world.authoritativeState;
    window.foldback_test_state.totalRollbacks = world.totalRollbacks;

    if (res.type === 'abort') {
        alert("Game ID Mismatch!");
        return;
    }
    
    if (res.tick !== undefined) {
        const ahead = world.currentTick - res.tick;
        document.getElementById('netStats').innerText = 
            `[${protocol.toUpperCase()}] ID: ${world.myPlayerId} | Tick: ${res.tick} (+${ahead}) | Status: ${world.localState.status} | RTT: ${world.rtt}ms | Rollbacks: ${world.totalRollbacks}`;
    }
}

function renderLoop() {
    // Update test state
    window.foldback_test_state.clientState = world.localState;

    airhockeyRender(ctx, canvas, world.localState, 0, world.myPlayerId, world.msPerTick);
    requestAnimationFrame(renderLoop);
}
requestAnimationFrame(renderLoop);

function sendInput() {
    if (connection.isOpen() && world.myPlayerId !== null) {
        const serverTick = world.authoritativeState.tick;
        const lead = world.currentTick - serverTick;

        if (lead < world.maxLead) {
            // Convert mouse screen coords to table fixed-point coords
            const centerX = canvas.width / 2;
            const centerY = canvas.height / 2;
            
            const margin = 1.1;
            const unitsW = (8000 / 1000) * margin;
            const unitsH = (12000 / 1000) * margin;
            const renderScale = Math.min(canvas.width / unitsW, canvas.height / unitsH);

            const tx = fpRound(((mouseX - centerX) / renderScale) * 1000);
            const ty = fpRound(((mouseY - centerY) / renderScale) * 1000);
            
            const nextTick = world.currentTick + 1;
            const input = { tx, ty, t: nextTick };
            
            connection.send(`(:tx ${tx} :ty ${ty} :t ${nextTick})`);
            
            // Update test state
            window.foldback_test_state.lastInputSent = { input, tick: nextTick };

            if (!world.inputBuffer.has(nextTick)) world.inputBuffer.set(nextTick, {});
            world.inputBuffer.get(nextTick)[world.myPlayerId] = input;
            
            const inputsForTick = {};
            inputsForTick[world.myPlayerId] = input;
            
            world.localState = airhockeyUpdate(world.localState, inputsForTick);
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

canvas.addEventListener('mousemove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;
});

function onOpen() {
    console.log(`${protocol} Open!`);
    document.getElementById('netStats').innerText = "Connected! Waiting for ID...";
    connection.send("()"); 
    sendInput();
}

async function connectWS() {
    const ws = new WebSocket(`ws://${window.location.host}/ws`);
    ws.onopen = onOpen;
    ws.onmessage = (e) => onMessage(e.data);
    connection = { send: (data) => ws.send(data), isOpen: () => ws.readyState === WebSocket.OPEN };
}

async function connectWebRTC() {
    const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
    const dc = pc.createDataChannel("foldback", { ordered: false, maxRetransmits: 0 });
    dc.onopen = onOpen;
    dc.onmessage = (e) => onMessage(e.data);
    connection = { send: (data) => dc.send(data), isOpen: () => dc.readyState === "open" };
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await new Promise(resolve => {
        if (pc.iceGatheringState === 'complete') resolve();
        else pc.onicegatheringstatechange = () => { if (pc.iceGatheringState === 'complete') resolve(); };
    });
    const response = await fetch('/offer', { method: 'POST', body: JSON.stringify(pc.localDescription) });
    const answer = await response.json();
    await pc.setRemoteDescription(answer);
}

if (protocol === 'webrtc') connectWebRTC();
else connectWS();
