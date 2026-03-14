/**
 * Generic FoldBack Engine Logic
 * Shared between Server (Lisp/JS) and Client (JS)
 */

export class FoldBackWorld {
    constructor(expectedGameId) {
        this.history = new Map();      // tick -> state (our PREDICTIONS)
        this.inputBuffer = new Map();  // tick -> input
        this.currentTick = 0;
        this.myPlayerId = null;
        this.totalRollbacks = 0;
        this.expectedGameId = expectedGameId;
        
        // Reconciliation settings
        this.reconciliationThresholdSq = 0.01; // 0.1 units squared
        this.comparisonFn = null; // Optional custom comparison (stateA, stateB) -> boolean (true if match)

        // Timing
        this.tickRate = 60;
        this.msPerTick = 1000 / 60; // Updated from server welcome

        // Latency tracking
        this.rtt = 0;
        this.maxLead = 10; // Default max lead in ticks
        this.pings = new Map(); // pingId -> timestamp
        this.lastPingTime = 0;

        this.authoritativeState = { 
            tick: 0, 
            players: {}, 
            customState: { level: [], bombs: {}, explosions: {}, bots: [] } 
        };

        this.localState = { 
            tick: 0, 
            players: {}, 
            customState: { level: [], bombs: {}, explosions: {}, bots: [] } 
        };
    }

    reset(state) {
        this.localState = JSON.parse(JSON.stringify(state));
        this.currentTick = state.tick;
        this.history.set(state.tick, JSON.parse(JSON.stringify(state)));
    }
}

/**
 * Generic simulation loop: calls simulationFn with state and inputs.
 */
export function updateGame(state, inputs, simulationFn) {
    return simulationFn(state, inputs);
}

/**
 * Rewind history to targetTick and re-simulate to the present.
 */
export function rollbackAndResimulate(world, targetTick, inputsMap, simulationFn) {
    let startState = world.history.get(targetTick - 1);
    if (!startState) return;

    for (let t = targetTick; t <= world.currentTick; t++) {
        let curState = world.history.get(t - 1) || startState;
        let nextState = updateGame(curState, inputsMap.get(t) || {}, simulationFn);
        world.history.set(t, nextState);
    }
}

/**
 * Authoritative reconciliation core
 */
export function processServerMessage(world, data, simulationFn, applyDeltaFn, syncFn) {
    const delta = JSON.parse(data);

    // Handle Ping Response (uppercase or legacy lowercase)
    const pongVal = delta.PONG ?? delta.pong;
    if (pongVal !== undefined) {
        const sentTime = world.pings.get(pongVal);
        if (sentTime) {
            world.rtt = Date.now() - sentTime;
            // Lead limit: Half RTT in ticks + 2 buffer
            world.maxLead = Math.ceil((world.rtt / 2) / world.msPerTick) + 2;
            world.pings.delete(pongVal);
        }
        return { type: 'pong' };
    }

    // Handle Welcome Packet (uppercase or legacy lowercase)
    const yourId = delta.YOUR_ID ?? delta.your_id;
    if (yourId !== undefined) {
        const gameId = delta.GAME_ID ?? delta.game_id;
        if (world.expectedGameId && gameId !== world.expectedGameId) {
            console.error(`GAME ID MISMATCH! Expected: ${world.expectedGameId}, Got: ${gameId}`);
            return { type: 'abort', reason: 'id_mismatch' };
        }
        world.myPlayerId = yourId;
        const tickRate = delta.TICK_RATE ?? delta.tick_rate;
        if (tickRate) {
            world.tickRate = tickRate;
            world.msPerTick = 1000 / tickRate;
        }
        return { type: 'welcome', id: yourId };
    }

    const serverTick = delta.TICK ?? delta.t;
    if (serverTick === undefined) return { type: 'error' };

    // Track whether client had a prediction for this tick (before we modify history)
    const hadPrediction = world.history.has(serverTick);

    // 1. Apply delta to authoritativeState
    world.authoritativeState = applyDeltaFn(world.authoritativeState, delta);

    // 2. Reconciliation
    if (world.myPlayerId !== null && hadPrediction) {
        const predictedState = world.history.get(serverTick);
        const myPredicted = predictedState.players[world.myPlayerId];
        const myAuthoritative = world.authoritativeState.players[world.myPlayerId];

        // Detect structural changes (player count, status) that position check would miss
        const predictedPlayerCount = Object.keys(predictedState.players).length;
        const authoritativePlayerCount = Object.keys(world.authoritativeState.players).length;
        const structuralChange = predictedPlayerCount !== authoritativePlayerCount
            || predictedState.status !== world.authoritativeState.status;

        if (structuralChange || (myPredicted && myAuthoritative)) {
            let mispredicted = structuralChange;

            if (!mispredicted && world.comparisonFn) {
                mispredicted = !world.comparisonFn(predictedState, world.authoritativeState);
            } else if (!mispredicted) {
                const dx = myPredicted.x - myAuthoritative.x;
                const dy = myPredicted.y - myAuthoritative.y;
                const distSq = dx * dx + dy * dy;
                mispredicted = distSq > world.reconciliationThresholdSq;
            }
            
            if (mispredicted) {
                if (typeof window !== 'undefined' && window.foldback_test_state) {
                    window.foldback_test_state.lastRollback = {
                        tick: serverTick,
                        predicted: myPredicted,
                        authoritative: myAuthoritative
                    };
                }
                world.totalRollbacks++;
                world._lastRollbackTick = serverTick;
                // 1. Set the foundation to the authoritative truth
                world.history.set(serverTick, JSON.parse(JSON.stringify(world.authoritativeState)));
                // 2. Re-simulate from serverTick + 1 to currentTick
                rollbackAndResimulate(world, serverTick + 1, world.inputBuffer, simulationFn);
                world.localState = JSON.parse(JSON.stringify(world.history.get(world.currentTick)));
            } else {
                // Foundation Fix: update history with authoritative state and resimulate
                // forward so predictions stay consistent with the corrected foundation
                world.history.set(serverTick, JSON.parse(JSON.stringify(world.authoritativeState)));
                if (serverTick < world.currentTick) {
                    rollbackAndResimulate(world, serverTick + 1, world.inputBuffer, simulationFn);
                    world.localState = JSON.parse(JSON.stringify(world.history.get(world.currentTick)));
                }
            }
        }
    } else if (world.myPlayerId !== null) {
        world.history.set(serverTick, JSON.parse(JSON.stringify(world.authoritativeState)));
    }

    // Initial sync, jump forward, or passive follow (no active prediction)
    if (world.localState.tick === 0 || serverTick > world.currentTick + 60
        || (!hadPrediction && serverTick > world.currentTick)) {
        world.reset(world.authoritativeState);
    }

    // Cleanup old history
    if (world.history.size > 120) {
        const minTick = serverTick - 120;
        for (let t of world.history.keys()) if (t < minTick) world.history.delete(t);
        for (let t of world.inputBuffer.keys()) if (t < minTick) world.inputBuffer.delete(t);
    }

    // Update non-predicted entities
    syncFn(world.localState, world.authoritativeState, world.myPlayerId);

    // Expose stats for testing (Playwright can poll window.foldbackStats)
    if (typeof window !== 'undefined') {
        window.foldbackStats = {
            rollbackCount: world.totalRollbacks,
            lastRollbackTick: world._lastRollbackTick || 0,
            lastServerTick: serverTick,
        };
    }

    return { type: 'tick', tick: serverTick };
}
