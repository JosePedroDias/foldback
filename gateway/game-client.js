/**
 * Shared game client bootstrap for FoldBack.
 * Handles networking, tick loop, input buffering, and prediction.
 * Games provide their specific logic via the config object.
 */

import { FoldBackWorld, processServerMessage } from './foldback-engine.js';

/**
 * Create and start a game client.
 *
 * @param {Object} config
 * @param {string}   config.gameName      - Game identifier (must match server)
 * @param {Function} config.updateFn      - (state, inputs) => newState (not needed if prediction=false)
 * @param {Function} config.applyDeltaFn  - (baseState, delta) => newState
 * @param {Function} config.syncFn        - (localState, serverState, myPlayerId) => void
 * @param {Function} config.render        - (world) => void — called each frame
 * @param {Function} config.getInput      - (world) => { local, wire } | null
 *   Return null to skip input this tick (e.g., game not ACTIVE).
 *   TICK is added automatically to both local (.t) and wire (.TICK) when prediction=true.
 * @param {boolean}  [config.prediction=true] - Enable client-side prediction.
 *   When false, the client is purely authoritative: it sends inputs and renders
 *   whatever the server sends back. No local simulation, rollback, or history.
 * @param {Function} [config.onBeforeMessage] - (world) => void
 * @param {Function} [config.onAfterMessage]  - (world, res) => void
 * @param {Function} [config.onAfterInput]    - (world) => void — after local prediction step
 * @param {Function} [config.onRender]        - (world) => void — after render each frame
 * @param {Function} [config.init]            - async () => void — called before connecting
 * @returns {{ world: FoldBackWorld }}
 */
export function createGameClient(config) {
    const {
        gameName,
        updateFn,
        applyDeltaFn,
        syncFn,
        render,
        getInput,
        prediction = true,
        onBeforeMessage,
        onAfterMessage,
        onAfterInput,
        onRender,
        init,
    } = config;

    const urlParams = new URLSearchParams(window.location.search);
    const protocol = urlParams.get('protocol') || 'webrtc';

    const world = new FoldBackWorld(gameName);
    window.world = world;

    window.foldback_test_state = {
        clientState: null,
        serverState: null,
        lastInputSent: null,
        lastRollback: null,
        totalRollbacks: 0,
    };

    let connection = { send: () => {}, isOpen: () => false };

    function onMessage(data) {
        if (onBeforeMessage) onBeforeMessage(world);

        const res = processServerMessage(world, data, updateFn, applyDeltaFn, syncFn);

        window.foldback_test_state.serverState = world.authoritativeState;
        window.foldback_test_state.totalRollbacks = world.totalRollbacks;

        if (res.type === 'abort') {
            alert("Game ID Mismatch!");
            return;
        }

        if (res.tick !== undefined) {
            const pCount = Object.keys(world.localState.players).length;
            if (prediction) {
                const ahead = world.currentTick - res.tick;
                document.getElementById('netStats').innerText =
                    `[${protocol.toUpperCase()}] ID: ${world.myPlayerId} | Tick: ${res.tick} (+${ahead}) | RTT: ${world.rtt}ms | Rollbacks: ${world.totalRollbacks} | Players: ${pCount}`;
            } else {
                document.getElementById('netStats').innerText =
                    `[${protocol.toUpperCase()}] ID: ${world.myPlayerId} | Tick: ${res.tick} | RTT: ${world.rtt}ms | Players: ${pCount}`;
            }
        }

        if (onAfterMessage) onAfterMessage(world, res);
    }

    function tick() {
        if (connection.isOpen() && world.myPlayerId !== null) {
            if (prediction) {
                const serverTick = world.authoritativeState.tick;
                const lead = world.currentTick - serverTick;

                if (lead < world.maxLead) {
                    const inputResult = getInput(world);

                    if (inputResult) {
                        const nextTick = world.currentTick + 1;
                        const local = { ...inputResult.local, t: nextTick };
                        const wire = { ...inputResult.wire, TICK: nextTick };

                        connection.send(JSON.stringify(wire));

                        window.foldback_test_state.lastInputSent = { input: local, tick: nextTick };

                        if (!world.inputBuffer.has(nextTick)) world.inputBuffer.set(nextTick, {});
                        world.inputBuffer.get(nextTick)[world.myPlayerId] = local;

                        const inputsForTick = {};
                        inputsForTick[world.myPlayerId] = local;

                        world.localState = updateFn(world.localState, inputsForTick);
                        world.currentTick = nextTick;
                        world.history.set(nextTick, JSON.parse(JSON.stringify(world.localState)));

                        if (onAfterInput) onAfterInput(world);
                    }
                }
            } else {
                // Authoritative-only: send input to server, no local simulation
                const inputResult = getInput(world);
                if (inputResult) {
                    connection.send(JSON.stringify(inputResult.wire));
                }
            }

            const now = Date.now();
            if (now - world.lastPingTime > 500) {
                const pingId = now;
                world.pings.set(pingId, now);
                connection.send(JSON.stringify({ TYPE: "PING", ID: pingId }));
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

        window.foldback_test_state.clientState = world.localState;
        render(world);
        if (onRender) onRender(world);
        requestAnimationFrame(gameLoop);
    }

    window.addEventListener('beforeunload', () => {
        if (connection.isOpen()) {
            connection.send(JSON.stringify({ TYPE: "LEAVE" }));
        }
    });

    function onOpen() {
        console.log(`${protocol} Open!`);
        document.getElementById('netStats').innerText = "Connected! Waiting for ID...";
        connection.send(JSON.stringify({ TYPE: "JOIN" }));
        const joinRetry = setInterval(() => {
            if (world.myPlayerId !== null) { clearInterval(joinRetry); return; }
            if (connection.isOpen()) connection.send(JSON.stringify({ TYPE: "JOIN" }));
        }, 1000);
    }

    function connectWS() {
        const ws = new WebSocket(`ws://${window.location.host}/ws/${gameName}`);
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
        const response = await fetch(`/offer/${gameName}`, { method: 'POST', body: JSON.stringify(pc.localDescription) });
        const answer = await response.json();
        await pc.setRemoteDescription(answer);
    }

    async function start() {
        if (init) await init();
        if (protocol === 'webrtc') connectWebRTC();
        else connectWS();
        requestAnimationFrame(gameLoop);
    }

    start();

    return { world };
}
