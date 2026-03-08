/**
 * Sumo-Specific Game Logic (Fixed-Point Port)
 */

import { fpAdd, fpMul, fpDistSq, fpToFloat, fpFromFloat, fbRandInt } from '../fixed-point.js';
import { fpCirclesOverlapP, fpPushCircles } from '../physics.js';

const SUMO_RING_RADIUS = 10000;
const SUMO_PLAYER_RADIUS = 500;
const SUMO_ACCELERATION = 10;
const SUMO_FRICTION = 950;
const SUMO_PUSH_FORCE = 5;

const COLORS = ["#3498db", "#e74c3c", "#2ecc71", "#f1c40f", "#9b59b6", "#1abc9c", "#e67e22"];

export function makeSumoPlayer(x = 0, y = 0, h = 100, deathTick = null) {
    return { x, y, vx: 0, vy: 0, h, dt: deathTick };
}

export function sumoJoin(playerId, state) {
    // Return a dummy player at 0,0. 
    // The server will provide the authoritative random spawn position.
    return makeSumoPlayer(0, 0);
}

export function sumoUpdate(state, inputs) {
    let nextTick = (state.tick || 0) + 1;
    let nextPlayers = { ...state.players };

    // 1. Movement and Friction
    for (let pid in nextPlayers) {
        let p = { ...nextPlayers[pid] };
        let input = (inputs && inputs[pid]) || {};

        if (p.h <= 0) continue;

        const dx = input.dx || 0;
        const dy = input.dy || 0;

        // Apply friction first, then acceleration
        // Matches Lisp: (fp-add (fp-mul vx +sumo-friction+) (fp-mul idx +sumo-acceleration+))
        p.vx = fpAdd(fpMul(p.vx || 0, SUMO_FRICTION), fpMul(fpFromFloat(dx), SUMO_ACCELERATION));
        p.vy = fpAdd(fpMul(p.vy || 0, SUMO_FRICTION), fpMul(fpFromFloat(dy), SUMO_ACCELERATION));

        // Update position
        p.x = fpAdd(p.x, p.vx);
        p.y = fpAdd(p.y, p.vy);

        // Check ring boundary
        const distSq = fpAdd(fpMul(p.x, p.x), fpMul(p.y, p.y));
        const limitSq = fpMul(SUMO_RING_RADIUS, SUMO_RING_RADIUS);
        if (distSq > limitSq) {
            p.h = 0; // Fallen out!
            p.dt = state.tick;
        }

        nextPlayers[pid] = p;
    }

    // 2. Interaction: Player-Player Collision
    // Using simple Lisp-like resolution for cross-platform matching
    let finalPlayers = { ...nextPlayers };
    for (let id1 in nextPlayers) {
        for (let id2 in nextPlayers) {
            if (id1 === id2) continue;
            let p1 = nextPlayers[id1];
            let p2 = nextPlayers[id2];
            if (p1.h <= 0 || p2.h <= 0) continue;

            if (fpCirclesOverlapP(p1.x, p1.y, SUMO_PLAYER_RADIUS, p2.x, p2.y, SUMO_PLAYER_RADIUS)) {
                const res = fpPushCircles(p1.x, p1.y, SUMO_PLAYER_RADIUS, p2.x, p2.y, SUMO_PLAYER_RADIUS);
                
                // Deterministic Push matching Lisp: vx += force * (nx > 0 ? 1 : -1)
                const forceX = (res.nx > 0) ? SUMO_PUSH_FORCE : -SUMO_PUSH_FORCE;
                const forceY = (res.ny > 0) ? SUMO_PUSH_FORCE : -SUMO_PUSH_FORCE;
                
                finalPlayers[id1] = { 
                    ...p1, 
                    vx: fpAdd(p1.vx, forceX), 
                    vy: fpAdd(p1.vy, forceY) 
                };
                // x will be updated next tick by velocity
            }
        }
    }

    return { ...state, tick: nextTick, players: finalPlayers };
}

export function sumoApplyDelta(baseState, delta) {
    const newState = JSON.parse(JSON.stringify(baseState));
    newState.tick = delta.t;
    if (delta.p) {
        delta.p.forEach(dp => {
            newState.players[dp.id] = dp;
        });
    }
    return newState;
}

export function sumoSync(localState, serverState, myPlayerId) {
    // 1. Sync players from server
    for (let id in serverState.players) {
        const sp = serverState.players[id];
        // Use loose equality because myPlayerId might be a number and id is a string key
        if (id != myPlayerId) {
            localState.players[id] = sp;
        } else {
            // For the local player, we ONLY sync authoritative health/death-tick.
            // We do NOT sync x, y, vx, vy because that would kill prediction.
            if (localState.players[id]) {
                localState.players[id].h = sp.h;
                localState.players[id].dt = sp.dt;
                localState.players[id].id = sp.id; // Ensure id is kept for rendering color
            } else {
                localState.players[id] = sp;
            }
        }
    }
    // 2. Remove players that are no longer in the server state
    for (let id in localState.players) {
        if (!serverState.players[id]) {
            delete localState.players[id];
        }
    }
}

export function sumoRender(ctx, canvas, localState, TILE_SIZE) {
    const centerX = canvas.width / 2;
    const centerY = canvas.height / 2;
    const scale = 0.025; // 600px / 24000 units? (Ring is 10000 units, 250px)

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Draw Ring
    ctx.strokeStyle = "#fff";
    ctx.lineWidth = 5;
    ctx.beginPath();
    ctx.arc(centerX, centerY, SUMO_RING_RADIUS * scale, 0, Math.PI * 2);
    ctx.stroke();

    // Draw Players
    for (let id in localState.players) {
        const p = localState.players[id];
        if (p.h <= 0) continue;

        // Use p.id for consistent color if available, otherwise fallback to index id
        const colorId = (p.id !== undefined) ? p.id : id;
        ctx.fillStyle = COLORS[colorId % COLORS.length];
        
        ctx.beginPath();
        // FIXED: Apply scale to raw fixed-point coordinates (integer), NOT the float version.
        // Ring used SUMO_RING_RADIUS * scale (10000 * 0.025 = 250).
        // Players must match: p.x * 0.025.
        ctx.arc(centerX + p.x * scale, centerY + p.y * scale, SUMO_PLAYER_RADIUS * scale, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = "#fff";
        ctx.lineWidth = 2;
        ctx.stroke();
    }
}
