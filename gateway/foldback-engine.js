/**
 * Generic FoldBack Engine Logic
 * Shared between Server (Lisp/JS) and Client (JS)
 */

class FoldBackWorld {
    constructor() {
        this.history = new Map();      // tick -> state (our PREDICTIONS)
        this.inputBuffer = new Map();  // tick -> input
        this.currentTick = 0;
        this.myPlayerId = null;
        this.totalRollbacks = 0;
        
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
function updateGame(state, inputs, simulationFn) {
    return simulationFn(state, inputs);
}

/**
 * Rewind history to targetTick and re-simulate to the present.
 */
function rollbackAndResimulate(world, targetTick, inputsMap, simulationFn) {
    let startState = world.history.get(targetTick);
    if (!startState) return;

    for (let t = targetTick + 1; t <= world.currentTick; t++) {
        let curState = world.history.get(t - 1) || startState;
        let nextState = updateGame(curState, inputsMap.get(t) || {}, simulationFn);
        world.history.set(t, nextState);
    }
}

/**
 * Authoritative reconciliation core
 */
function processServerMessage(world, data, simulationFn, applyDeltaFn, syncFn) {
    const delta = JSON.parse(data);

    // Handle Welcome Packet
    if (delta.your_id !== undefined) {
        world.myPlayerId = delta.your_id;
        return { type: 'welcome', id: delta.your_id };
    }

    const serverTick = delta.t;
    if (serverTick === undefined) return { type: 'error' };

    // 1. Apply delta to authoritativeState
    world.authoritativeState = applyDeltaFn(world.authoritativeState, delta);

    // 2. Reconciliation
    if (world.myPlayerId !== null && world.history.has(serverTick)) {
        const predictedState = world.history.get(serverTick);
        const myPredicted = predictedState.players[world.myPlayerId];
        const myAuthoritative = world.authoritativeState.players[world.myPlayerId];

        if (myPredicted && myAuthoritative) {
            const dist = Math.sqrt(Math.pow(myPredicted.x - myAuthoritative.x, 2) + 
                                 Math.pow(myPredicted.y - myAuthoritative.y, 2));
            
            if (dist > 0.1) {
                console.warn(`DETECTION_MISPREDICTION at tick ${serverTick}! Deviation: ${dist}`);
                world.totalRollbacks++;
                world.history.set(serverTick, JSON.parse(JSON.stringify(world.authoritativeState)));
                rollbackAndResimulate(world, serverTick, world.inputBuffer, simulationFn);
                world.localState = JSON.parse(JSON.stringify(world.history.get(world.currentTick)));
            } else {
                // Foundation Fix
                world.history.set(serverTick, JSON.parse(JSON.stringify(world.authoritativeState)));
            }
        }
    } else if (world.myPlayerId !== null) {
        world.history.set(serverTick, JSON.parse(JSON.stringify(world.authoritativeState)));
    }

    // Initial sync or jump forward
    if (world.localState.tick === 0 || serverTick > world.currentTick + 60) {
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
    
    return { type: 'tick', tick: serverTick };
}

// Support Node.js/CommonJS environment for testing
if (typeof module !== 'undefined') {
    module.exports = { FoldBackWorld, updateGame, rollbackAndResimulate, processServerMessage };
}
