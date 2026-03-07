/**
 * Sumo-Specific Game Logic
 * Ported from src/sumo.lisp
 */

const RING_RADIUS = 10.0;
const PLAYER_RADIUS = 0.5;
const ACCELERATION = 0.015;
const FRICTION = 0.96;
const PUSH_FORCE = 0.05;
const RESPAWN_TIMEOUT = 180;

const COLORS = ["#3498db", "#e74c3c", "#2ecc71", "#f1c40f", "#9b59b6", "#1abc9c", "#e67e22"];

/**
 * Entry point for a single tick of the Sumo simulation.
 */
function sumoUpdate(state, inputs) {
    let nextTick = state.tick + 1;
    let nextPlayers = { ...state.players };

    // 1. Physics: Velocity, Friction, and Input Acceleration
    for (let pid in nextPlayers) {
        const p = nextPlayers[pid];
        if (p.h <= 0) {
            // Check for respawn (simplified prediction - actual respawn synced from server)
            if (p.dt !== undefined && p.dt !== null && (nextTick - p.dt) >= RESPAWN_TIMEOUT) {
                // We'll let the server sync the actual respawn position
            }
            nextPlayers[pid] = p;
            continue;
        }

        const input = (inputs && inputs[pid]) || {};
        const idx = input.dx || 0;
        const idy = input.dy || 0;

        let nvx = (p.vx || 0) * FRICTION + idx * ACCELERATION;
        let nvy = (p.vy || 0) * FRICTION + idy * ACCELERATION;
        let nx = p.x + nvx;
        let ny = p.y + nvy;
        let nh = p.h;
        let ndt = p.dt;

        // Boundary Check
        if ((nx * nx + ny * ny) > RING_RADIUS * RING_RADIUS) {
            nh = 0;
            ndt = state.tick;
        }

        nextPlayers[pid] = { ...p, x: nx, y: ny, vx: nvx, vy: nvy, h: nh, dt: ndt };
    }

    // 2. Interaction: Player-Player Collision (Deterministic Fix)
    for (let id1 in nextPlayers) {
        for (let id2 in nextPlayers) {
            if (id1 === id2) continue;
            let p1 = nextPlayers[id1];
            let p2 = nextPlayers[id2];
            if (p1.h <= 0 || p2.h <= 0) continue;

            const dx = p2.x - p1.x;
            const dy = p2.y - p1.y;
            const distSq = dx * dx + dy * dy;
            const minDist = PLAYER_RADIUS * 2.0;
            const minDistSq = minDist * minDist;

            if (distSq < minDistSq) {
                // Deterministic Push
                const forceX = (dx > 0) ? -PUSH_FORCE : PUSH_FORCE;
                const forceY = (dy > 0) ? -PUSH_FORCE : PUSH_FORCE;
                
                nextPlayers[id1] = {
                    ...p1,
                    vx: p1.vx + forceX,
                    vy: p1.vy + forceY
                };
            }
        }
    }

    return {
        ...state,
        tick: nextTick,
        players: nextPlayers
    };
}

function sumoApplyDelta(baseState, delta) {
    const newState = JSON.parse(JSON.stringify(baseState));
    newState.tick = delta.t;
    if (delta.p) {
        delta.p.forEach(dp => { 
            newState.players[dp.id] = dp;
        });
    }
    return newState;
}

function sumoSync(localState, serverState, myPlayerId) {
    for (let id in serverState.players) {
        if (id != myPlayerId) {
            localState.players[id] = serverState.players[id];
        } else if (localState.players[id]) {
            localState.players[id].h = serverState.players[id].h;
        } else {
            localState.players[id] = serverState.players[id];
        }
    }
}

function sumoRender(ctx, canvas, localState, TILE_SIZE) {
    const centerX = canvas.width / 2;
    const centerY = canvas.height / 2;
    const renderScale = 20;

    if (canvas.width !== 600) {
        canvas.width = 600;
        canvas.height = 600;
    }

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    ctx.strokeStyle = "#fff";
    ctx.lineWidth = 5;
    ctx.beginPath();
    ctx.arc(centerX, centerY, RING_RADIUS * renderScale, 0, Math.PI * 2);
    ctx.stroke();
    ctx.fillStyle = "#333";
    ctx.fill();

    for (let id in localState.players) {
        const p = localState.players[id];
        if (p.h <= 0) continue;

        ctx.fillStyle = COLORS[id % COLORS.length];
        ctx.beginPath();
        ctx.arc(centerX + p.x * renderScale, centerY + p.y * renderScale, PLAYER_RADIUS * renderScale, 0, Math.PI * 2);
        ctx.fill();
        
        ctx.fillStyle = "#fff";
        ctx.font = "12px Arial";
        ctx.textAlign = "center";
        ctx.fillText(`ID ${id}`, centerX + p.x * renderScale, centerY + p.y * renderScale - 15);
    }
}

// Support Node.js/CommonJS environment for testing
if (typeof module !== 'undefined') {
    module.exports = {
        sumoUpdate,
        sumoApplyDelta,
        sumoSync,
        sumoRender
    };
}
