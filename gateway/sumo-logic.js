/**
 * Sumo-Specific Game Logic (Fixed-Point Port)
 */

if (typeof require !== 'undefined') {
    const fp = require('./fixed-point.js');
    const physics = require('./physics.js');
    Object.assign(global, fp);
    Object.assign(global, physics);
}

const SUMO_RING_RADIUS = 10000;
const SUMO_PLAYER_RADIUS = 500;
const SUMO_ACCELERATION = 15;
const SUMO_FRICTION = 960;
const SUMO_PUSH_FORCE = 50;
const SUMO_RESPAWN_TIMEOUT = 180;

const COLORS = ["#3498db", "#e74c3c", "#2ecc71", "#f1c40f", "#9b59b6", "#1abc9c", "#e67e22"];

function sumoUpdate(state, inputs) {
    let nextTick = state.tick + 1;
    let nextPlayers = { ...state.players };

    // 1. Physics: Velocity, Friction, and Input Acceleration
    for (let pid in nextPlayers) {
        const p = nextPlayers[pid];
        if (p.h <= 0) {
            nextPlayers[pid] = p;
            continue;
        }

        const input = (inputs && inputs[pid]) || {};
        const idx = fpFromFloat(input.dx || 0);
        const idy = fpFromFloat(input.dy || 0);

        let nvx = fpAdd(fpMul(p.vx || 0, SUMO_FRICTION), fpMul(idx, SUMO_ACCELERATION));
        let nvy = fpAdd(fpMul(p.vy || 0, SUMO_FRICTION), fpMul(idy, SUMO_ACCELERATION));
        let nx = fpAdd(p.x, nvx);
        let ny = fpAdd(p.y, nvy);
        let nh = p.h;
        let ndt = p.dt;

        // Boundary Check: x^2 + y^2 > r^2
        if (fpAdd(fpMul(nx, nx), fpMul(ny, ny)) > fpMul(SUMO_RING_RADIUS, SUMO_RING_RADIUS)) {
            nh = 0;
            ndt = state.tick;
        }

        nextPlayers[pid] = { ...p, x: nx, y: ny, vx: nvx, vy: nvy, h: nh, dt: ndt };
    }

    // 2. Interaction: Player-Player Collision (using shared helper)
    for (let id1 in nextPlayers) {
        for (let id2 in nextPlayers) {
            if (id1 === id2) continue;
            let p1 = nextPlayers[id1];
            let p2 = nextPlayers[id2];
            if (p1.h <= 0 || p2.h <= 0) continue;

            if (fpCirclesOverlapP(p1.x, p1.y, SUMO_PLAYER_RADIUS, p2.x, p2.y, SUMO_PLAYER_RADIUS)) {
                const res = fpPushCircles(p1.x, p1.y, SUMO_PLAYER_RADIUS, p2.x, p2.y, SUMO_PLAYER_RADIUS);
                // Deterministic Push
                const forceX = (res.nx > 0) ? SUMO_PUSH_FORCE : -SUMO_PUSH_FORCE;
                const forceY = (res.ny > 0) ? SUMO_PUSH_FORCE : -SUMO_PUSH_FORCE;
                
                nextPlayers[id1] = {
                    ...p1,
                    vx: fpAdd(p1.vx, forceX),
                    vy: fpAdd(p1.vy, forceY)
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
    ctx.arc(centerX, centerY, (SUMO_RING_RADIUS/1000) * renderScale, 0, Math.PI * 2);
    ctx.stroke();
    ctx.fillStyle = "#333";
    ctx.fill();

    for (let id in localState.players) {
        const p = localState.players[id];
        if (p.h <= 0) continue;

        ctx.fillStyle = COLORS[id % COLORS.length];
        ctx.beginPath();
        ctx.arc(centerX + (p.x/1000) * renderScale, centerY + (p.y/1000) * renderScale, (SUMO_PLAYER_RADIUS/1000) * renderScale, 0, Math.PI * 2);
        ctx.fill();
        
        ctx.fillStyle = "#fff";
        ctx.font = "12px Arial";
        ctx.textAlign = "center";
        ctx.fillText(`ID ${id}`, centerX + (p.x/1000) * renderScale, centerY + (p.y/1000) * renderScale - 15);
    }
}

if (typeof module !== 'undefined') {
    module.exports = {
        sumoUpdate,
        sumoApplyDelta,
        sumoSync,
        sumoRender
    };
}
