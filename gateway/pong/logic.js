/**
 * Pong Game Logic — Tutorial Game
 * Simplest FoldBack game: two paddles, one ball, first to 11.
 */

import { fpClamp, fpDiv, fpMul } from '../fixed-point.js';

// --- Constants (Fixed-Point, scale 1000) ---
const PONG_TABLE_W = 12000;      // 12.0 units wide
const PONG_TABLE_H = 8000;       // 8.0 units tall
const PONG_PADDLE_X = 5500;      // paddle center at x = +/-5.5
const PONG_PADDLE_HALF_H = 750;  // paddle half-height (total 1.5 units)
const PONG_BALL_R = 150;         // ball radius
const PONG_BALL_SPEED = 80;      // initial ball vx per tick
const PONG_MAX_VY = 120;         // max vertical speed after paddle bounce
const PONG_MAX_SCORE = 11;
const PONG_WIN_RESET_TICKS = 600; // 10 seconds at 60Hz

function findBySide(players, side) {
    for (let pid in players) {
        if (players[pid].side === side) return pid;
    }
    return null;
}

function pongReset(state, nextTick, serveDir) {
    let resetPlayers = {};
    for (let pid in state.players) {
        resetPlayers[pid] = { ...state.players[pid], y: 0 };
    }
    return {
        tick: nextTick,
        players: resetPlayers,
        ball: { x: 0, y: 0, vx: serveDir * PONG_BALL_SPEED, vy: 0 },
        status: state.status
    };
}

export function pongUpdate(state, inputs) {
    const nextTick = state.tick + 1;
    let nextPlayers = { ...state.players };
    let nextBall = state.ball ? { ...state.ball } : null;
    let nextStatus = state.status || 'WAITING';

    // --- Status transitions ---

    // Player left during a non-waiting state → full reset
    if (nextStatus !== 'WAITING' && Object.keys(nextPlayers).length < 2) {
        let resetPlayers = {};
        for (let pid in nextPlayers) {
            resetPlayers[pid] = { ...nextPlayers[pid], sc: 0, y: 0 };
        }
        return { tick: nextTick, players: resetPlayers, ball: null, status: 'WAITING' };
    }

    // Win state → wait 10 seconds then reset
    if (nextStatus === 'P0_WINS' || nextStatus === 'P1_WINS') {
        const wt = state.winTick;
        if (wt !== undefined && (state.tick - wt) >= PONG_WIN_RESET_TICKS) {
            let resetPlayers = {};
            for (let pid in nextPlayers) {
                resetPlayers[pid] = { ...nextPlayers[pid], sc: 0, y: 0 };
            }
            return { tick: nextTick, players: resetPlayers, ball: null, status: 'WAITING' };
        }
        return { ...state, tick: nextTick };
    }

    if (nextStatus === 'WAITING' && Object.keys(nextPlayers).length >= 2) {
        nextStatus = 'ACTIVE';
        let resetState = pongReset({ ...state, status: 'ACTIVE' }, nextTick, 1);
        resetState.status = 'ACTIVE';
        return resetState;
    }

    if (nextStatus !== 'ACTIVE') {
        return { ...state, tick: nextTick };
    }

    // --- Update paddles ---
    const minY = -(PONG_TABLE_H / 2) + PONG_PADDLE_HALF_H;
    const maxY = (PONG_TABLE_H / 2) - PONG_PADDLE_HALF_H;

    for (let pid in nextPlayers) {
        const p = nextPlayers[pid];
        const input = (inputs && inputs[pid]) || {};
        const ty = (input.ty !== undefined) ? input.ty : p.y;
        const ny = fpClamp(ty, minY, maxY);
        nextPlayers[pid] = { ...p, y: ny };
    }

    // --- Update ball ---
    if (nextBall) {
        let bx = nextBall.x, by = nextBall.y;
        let bvx = nextBall.vx, bvy = nextBall.vy;
        const halfH = PONG_TABLE_H / 2;
        const br = PONG_BALL_R;

        // Move ball
        bx = bx + bvx;
        by = by + bvy;

        // Top/bottom wall bounce
        if (by + br >= halfH) {
            by = halfH - br;
            bvy = -bvy;
        }
        if (by - br <= -halfH) {
            by = -halfH + br;
            bvy = -bvy;
        }

        // Left paddle collision (side 0, x = -5500)
        if (bvx < 0) {
            const paddleEdge = -PONG_PADDLE_X;
            if (bx - br <= paddleEdge && bx >= paddleEdge) {
                const p0pid = findBySide(nextPlayers, 0);
                if (p0pid !== null) {
                    const py = nextPlayers[p0pid].y;
                    if (by + br >= py - PONG_PADDLE_HALF_H &&
                        by - br <= py + PONG_PADDLE_HALF_H) {
                        // Hit paddle
                        const relY = fpDiv(by - py, PONG_PADDLE_HALF_H);
                        const crel = fpClamp(relY, -1000, 1000);
                        bx = paddleEdge + br;
                        bvx = -bvx;
                        bvy = fpMul(crel, PONG_MAX_VY);
                    }
                }
            }
        }

        // Right paddle collision (side 1, x = 5500)
        if (bvx > 0) {
            const paddleEdge = PONG_PADDLE_X;
            if (bx + br >= paddleEdge && bx <= paddleEdge) {
                const p1pid = findBySide(nextPlayers, 1);
                if (p1pid !== null) {
                    const py = nextPlayers[p1pid].y;
                    if (by + br >= py - PONG_PADDLE_HALF_H &&
                        by - br <= py + PONG_PADDLE_HALF_H) {
                        // Hit paddle
                        const relY = fpDiv(by - py, PONG_PADDLE_HALF_H);
                        const crel = fpClamp(relY, -1000, 1000);
                        bx = paddleEdge - br;
                        bvx = -bvx;
                        bvy = fpMul(crel, PONG_MAX_VY);
                    }
                }
            }
        }

        // Goal detection
        if (bx <= -(PONG_TABLE_W / 2)) {
            // Ball exited left — Player 1 scores
            const scorerPid = findBySide(nextPlayers, 1);
            if (scorerPid !== null) {
                const newSc = (nextPlayers[scorerPid].sc || 0) + 1;
                nextPlayers[scorerPid] = { ...nextPlayers[scorerPid], sc: newSc };
                if (newSc >= PONG_MAX_SCORE) {
                    return { ...state, tick: nextTick, players: nextPlayers, ball: nextBall, status: 'P1_WINS', winTick: nextTick };
                } else {
                    return pongReset({ ...state, players: nextPlayers }, nextTick, -1);
                }
            }
        }

        if (bx >= PONG_TABLE_W / 2) {
            // Ball exited right — Player 0 scores
            const scorerPid = findBySide(nextPlayers, 0);
            if (scorerPid !== null) {
                const newSc = (nextPlayers[scorerPid].sc || 0) + 1;
                nextPlayers[scorerPid] = { ...nextPlayers[scorerPid], sc: newSc };
                if (newSc >= PONG_MAX_SCORE) {
                    return { ...state, tick: nextTick, players: nextPlayers, ball: nextBall, status: 'P0_WINS', winTick: nextTick };
                } else {
                    return pongReset({ ...state, players: nextPlayers }, nextTick, 1);
                }
            }
        }

        nextBall = { x: bx, y: by, vx: bvx, vy: bvy };
    }

    return { ...state, tick: nextTick, players: nextPlayers, ball: nextBall, status: nextStatus };
}

export function pongApplyDelta(baseState, delta) {
    const newState = JSON.parse(JSON.stringify(baseState));
    newState.tick = delta.TICK;
    newState.status = delta.STATUS;
    newState.winTick = delta.WIN_TICK;
    if (delta.BALL) {
        newState.ball = { x: delta.BALL.X, y: delta.BALL.Y, vx: delta.BALL.VX, vy: delta.BALL.VY };
    } else {
        newState.ball = null;
    }
    if (delta.PLAYERS) {
        const newPlayers = {};
        delta.PLAYERS.forEach(dp => {
            newPlayers[dp.ID] = { id: dp.ID, side: dp.SIDE, x: dp.X, y: dp.Y, sc: dp.SCORE };
        });
        newState.players = newPlayers;
    }
    return newState;
}

let lastServerState = null, currentServerState = null, lastSyncTime = 0;

export function pongSync(localState, serverState, myPlayerId) {
    lastServerState = currentServerState;
    currentServerState = JSON.parse(JSON.stringify(serverState));
    lastSyncTime = Date.now();
    localState.status = serverState.status;
    for (let id in serverState.players) {
        if (id != myPlayerId) {
            localState.players[id] = serverState.players[id];
        } else if (localState.players[id]) {
            localState.players[id].sc = serverState.players[id].sc;
        } else {
            localState.players[id] = serverState.players[id];
        }
    }
    for (let id in localState.players) {
        if (!serverState.players[id]) delete localState.players[id];
    }
}

export function pongRender(ctx, canvas, localState, TILE_SIZE, myPlayerId, msPerTick = 16.6) {
    const centerX = canvas.width / 2, centerY = canvas.height / 2;
    const margin = 1.15;
    const unitsW = (PONG_TABLE_W / 1000) * margin;
    const unitsH = (PONG_TABLE_H / 1000) * margin;
    const scale = Math.min(canvas.width / unitsW, canvas.height / unitsH);

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Table outline
    const tw = (PONG_TABLE_W / 2000) * scale, th = (PONG_TABLE_H / 2000) * scale;
    ctx.strokeStyle = '#555';
    ctx.lineWidth = 2;
    ctx.strokeRect(centerX - tw, centerY - th, tw * 2, th * 2);

    // Center line (dashed)
    ctx.setLineDash([8, 8]);
    ctx.strokeStyle = '#444';
    ctx.beginPath();
    ctx.moveTo(centerX, centerY - th);
    ctx.lineTo(centerX, centerY + th);
    ctx.stroke();
    ctx.setLineDash([]);

    const now = Date.now();
    const lerpFactor = Math.min(1.0, (now - lastSyncTime) / msPerTick);

    // Paddles
    const pw = (200 / 1000) * scale;  // paddle width in px
    const ph = (PONG_PADDLE_HALF_H / 1000) * scale;  // paddle half-height in px

    for (let id in localState.players) {
        let p = localState.players[id];
        // Interpolate remote player
        if (id != myPlayerId && currentServerState && lastServerState &&
            lastServerState.players[id] && currentServerState.players[id]) {
            const p1 = lastServerState.players[id];
            const p2 = currentServerState.players[id];
            p = { ...p, y: p1.y + (p2.y - p1.y) * lerpFactor };
        }
        const px = centerX + (p.x / 1000) * scale;
        const py = centerY + (p.y / 1000) * scale;
        ctx.fillStyle = (p.side === 0) ? '#3498db' : '#e74c3c';
        ctx.fillRect(px - pw / 2, py - ph, pw, ph * 2);
    }

    // Ball (predicted locally, corrected by reconciliation)
    const ball = localState.ball;
    if (ball) {
        const bx = centerX + (ball.x / 1000) * scale;
        const by = centerY + (ball.y / 1000) * scale;
        const br = (PONG_BALL_R / 1000) * scale;
        ctx.fillStyle = '#ecf0f1';
        ctx.beginPath();
        ctx.arc(bx, by, br, 0, Math.PI * 2);
        ctx.fill();
    }

    // Score
    ctx.fillStyle = '#fff';
    ctx.font = 'bold 48px monospace';
    ctx.textAlign = 'center';
    const p0pid = findBySide(localState.players, 0);
    const p1pid = findBySide(localState.players, 1);
    const s0 = (p0pid !== null && localState.players[p0pid]) ? (localState.players[p0pid].sc || 0) : 0;
    const s1 = (p1pid !== null && localState.players[p1pid]) ? (localState.players[p1pid].sc || 0) : 0;
    ctx.fillText(`${s0}`, centerX - 60, 50);
    ctx.fillText(`${s1}`, centerX + 60, 50);
    ctx.font = '14px monospace';
    ctx.fillStyle = '#888';
    ctx.fillText(localState.status || '', centerX, canvas.height - 15);
}
