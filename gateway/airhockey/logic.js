/**
 * Air Hockey Game Logic (Segment-based Table)
 */

import { fpFromFloat, fpClamp, fpSub, fpMul, fpAdd, fpDistSq, fpSqrt, fpDiv } from '../fixed-point.js';
import { fpCirclesOverlapP, fpPushCircles, fpClosestPointOnSegment } from '../physics.js';

const AH_TABLE_WIDTH = 8000;
const AH_TABLE_HEIGHT = 12000;
const AH_PADDLE_RADIUS = 400;
const AH_PUCK_RADIUS = 300;
const AH_GOAL_WIDTH = 2000;
const AH_MAX_SCORE = 11;
const AH_FRICTION = 990;
const AH_BOUNCE = 800;
const AH_CORNER_RADIUS = 1000;

function generateTableSegments() {
    const cr = AH_CORNER_RADIUS / 1000;
    const segments = [];

    function addSeg(x1, y1, x2, y2, type) {
        segments.push({ 
            x1: fpFromFloat(x1), y1: fpFromFloat(y1), 
            x2: fpFromFloat(x2), y2: fpFromFloat(y2), 
            type 
        });
    }

    function addCorner(cx, cy, startAngle, endAngle) {
        const steps = 6;
        for (let i = 0; i < steps; i++) {
            const a1 = startAngle + i * ((endAngle - startAngle) / steps);
            const a2 = startAngle + (i + 1) * ((endAngle - startAngle) / steps);
            addSeg(cx + cr * Math.cos(a1), cy + cr * Math.sin(a1),
                   cx + cr * Math.cos(a2), cy + cr * Math.sin(a2),
                   'wall');
        }
    }

    const xLf = -(AH_TABLE_WIDTH / 2000), xRf = (AH_TABLE_WIDTH / 2000);
    const yTf = -(AH_TABLE_HEIGHT / 2000), yBf = (AH_TABLE_HEIGHT / 2000);
    const crf = AH_CORNER_RADIUS / 1000;
    const gwf = AH_GOAL_WIDTH / 2000;

    addSeg(xLf, yBf - crf, xLf, yTf + crf, 'wall');
    addSeg(xRf, yTf + crf, xRf, yBf - crf, 'wall');
    addSeg(xRf - crf, yTf, gwf, yTf, 'wall');
    addSeg(-gwf, yTf, xLf + crf, yTf, 'wall');
    addSeg(gwf, yTf, -gwf, yTf, 'goal-top');
    addSeg(xLf + crf, yBf, -gwf, yBf, 'wall');
    addSeg(gwf, yBf, xRf - crf, yBf, 'wall');
    addSeg(-gwf, yBf, gwf, yBf, 'goal-bottom');

    addCorner(xRf - crf, yTf + crf, 1.5 * Math.PI, 2.0 * Math.PI);
    addCorner(xLf + crf, yTf + crf, Math.PI, 1.5 * Math.PI);
    addCorner(xLf + crf, yBf - crf, 0.5 * Math.PI, Math.PI);
    addCorner(xRf - crf, yBf - crf, 0, 0.5 * Math.PI);

    return segments;
}

export const AH_SEGMENTS = generateTableSegments();

export function airhockeyUpdate(state, inputs) {
    let nextTick = state.tick + 1;
    let nextPlayers = { ...state.players };
    let nextPuck = state.puck ? { ...state.puck } : null;
    let nextStatus = state.status || 'waiting';

    if (nextStatus === 'waiting' && Object.keys(nextPlayers).length >= 2) {
        nextStatus = 'active';
        nextPuck = { x: 0, y: 0, vx: 0, vy: 0 };
        for (let id in nextPlayers) {
            nextPlayers[id] = { ...nextPlayers[id], x: 0, y: (id == 0 ? -4000 : 4000), vx: 0, vy: 0 };
        }
    }

    if (nextStatus !== 'active') return { ...state, tick: nextTick };

    for (let pid in nextPlayers) {
        let p = nextPlayers[pid];
        let input = (inputs && inputs[pid]) || {};
        let targetX = (input.tx !== undefined) ? input.tx : p.x;
        let targetY = (input.ty !== undefined) ? input.ty : p.y;

        let halfW = AH_TABLE_WIDTH / 2, halfH = AH_TABLE_HEIGHT / 2;
        let minX = -halfW + AH_PADDLE_RADIUS, maxX = halfW - AH_PADDLE_RADIUS;
        let minY, maxY;

        if (parseInt(pid) === 0) {
            minY = -halfH + AH_PADDLE_RADIUS;
            maxY = -AH_PADDLE_RADIUS;
        } else {
            minY = AH_PADDLE_RADIUS;
            maxY = halfH - AH_PADDLE_RADIUS;
        }

        let nx = fpClamp(targetX, minX, maxX);
        let ny = fpClamp(targetY, minY, maxY);
        let vx = fpSub(nx, p.x);
        let vy = fpSub(ny, p.y);

        nextPlayers[pid] = { ...p, x: nx, y: ny, vx: vx, vy: vy };
    }

    if (nextPuck) {
        let px = nextPuck.x, py = nextPuck.y, pvx = nextPuck.vx, pvy = nextPuck.vy;
        pvx = fpMul(pvx, AH_FRICTION);
        pvy = fpMul(pvy, AH_FRICTION);
        px = fpAdd(px, pvx);
        py = fpAdd(py, pvy);

        if (Math.abs(px) > 4400 || Math.abs(py) > 6600) {
            return { ...state, tick: nextTick, puck: { x: 0, y: 0, vx: 0, vy: 0 } };
        }

        for (let pid in nextPlayers) {
            let p = nextPlayers[pid];
            if (fpCirclesOverlapP(px, py, AH_PUCK_RADIUS, p.x, p.y, AH_PADDLE_RADIUS)) {
                const res = fpPushCircles(px, py, AH_PUCK_RADIUS, p.x, p.y, AH_PADDLE_RADIUS);
                px = fpAdd(px, fpMul(res.nx, res.overlap));
                py = fpAdd(py, fpMul(res.ny, res.overlap));
                pvx = fpAdd(p.vx, fpMul(res.nx, 50));
                pvy = fpAdd(p.vy, fpMul(res.ny, 50));
            }
        }

        for (let seg of AH_SEGMENTS) {
            const closest = fpClosestPointOnSegment(px, py, seg.x1, seg.y1, seg.x2, seg.y2);
            let distSq = fpDistSq(px, py, closest.x, closest.y);

            if (distSq < fpMul(AH_PUCK_RADIUS, AH_PUCK_RADIUS)) {
                if (seg.type === 'wall') {
                    let dist = fpSqrt(distSq);
                    let nx = (dist === 0) ? 0 : fpDiv(fpSub(px, closest.x), dist);
                    let ny = (dist === 0) ? 0 : fpDiv(fpSub(py, closest.y), dist);
                    let overlap = AH_PUCK_RADIUS - dist;
                    px = fpAdd(px, fpMul(nx, overlap));
                    py = fpAdd(py, fpMul(ny, overlap));
                    let dot = fpAdd(fpMul(pvx, nx), fpMul(pvy, ny));
                    pvx = fpMul(fpSub(pvx, fpMul(fpMul(2000, nx), dot)), AH_BOUNCE);
                    pvy = fpMul(fpSub(pvy, fpMul(fpMul(2000, ny), dot)), AH_BOUNCE);
                }
            }
        }
        nextPuck = { x: px, y: py, vx: pvx, vy: pvy };
    }

    return { ...state, tick: nextTick, players: nextPlayers, puck: nextPuck, status: nextStatus };
}

export function airhockeyApplyDelta(baseState, delta) {
    const newState = JSON.parse(JSON.stringify(baseState));
    newState.tick = delta.t;
    newState.status = delta.s;
    if (delta.pk) newState.puck = delta.pk;
    if (delta.p) {
        delta.p.forEach(dp => { newState.players[dp.id] = dp; });
    }
    return newState;
}

let lastServerState = null, currentServerState = null, lastSyncTime = 0;

export function airhockeySync(localState, serverState, myPlayerId) {
    lastServerState = currentServerState;
    currentServerState = JSON.parse(JSON.stringify(serverState));
    lastSyncTime = Date.now();
    localState.status = serverState.status;
    localState.puck = serverState.puck;
    for (let id in serverState.players) {
        if (id != myPlayerId) localState.players[id] = serverState.players[id];
        else if (localState.players[id]) localState.players[id].sc = serverState.players[id].sc;
        else localState.players[id] = serverState.players[id];
    }
    for (let id in localState.players) {
        if (!serverState.players[id]) delete localState.players[id];
    }
}

export function airhockeyRender(ctx, canvas, localState, TILE_SIZE, myPlayerId) {
    const centerX = canvas.width / 2, centerY = canvas.height / 2;
    const margin = 1.1;
    const unitsW = (AH_TABLE_WIDTH / 1000) * margin, unitsH = (AH_TABLE_HEIGHT / 1000) * margin;
    const renderScale = Math.min(canvas.width / unitsW, canvas.height / unitsH);

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    ctx.strokeStyle = "#fff";
    ctx.lineWidth = 3;
    ctx.beginPath();
    for (let seg of AH_SEGMENTS) {
        if (seg.type === 'wall') {
            ctx.moveTo(centerX + (seg.x1/1000) * renderScale, centerY + (seg.y1/1000) * renderScale);
            ctx.lineTo(centerX + (seg.x2/1000) * renderScale, centerY + (seg.y2/1000) * renderScale);
        }
    }
    ctx.stroke();

    ctx.strokeStyle = "#e74c3c";
    ctx.lineWidth = 5;
    ctx.beginPath();
    for (let seg of AH_SEGMENTS) {
        if (seg.type !== 'wall') {
            ctx.moveTo(centerX + (seg.x1/1000) * renderScale, centerY + (seg.y1/1000) * renderScale);
            ctx.lineTo(centerX + (seg.x2/1000) * renderScale, centerY + (seg.y2/1000) * renderScale);
        }
    }
    ctx.stroke();

    ctx.strokeStyle = "rgba(255,255,255,0.3)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(centerX - (AH_TABLE_WIDTH/2000) * renderScale, centerY);
    ctx.lineTo(centerX + (AH_TABLE_WIDTH/2000) * renderScale, centerY);
    ctx.stroke();

    const now = Date.now(), lerpFactor = Math.min(1.0, (now - lastSyncTime) / 16.6);

    for (let id in localState.players) {
        let p = localState.players[id];
        if (id != myPlayerId && currentServerState && lastServerState && lastServerState.players[id] && currentServerState.players[id]) {
            const p1 = lastServerState.players[id], p2 = currentServerState.players[id];
            p = { x: p1.x + (p2.x - p1.x) * lerpFactor, y: p1.y + (p2.y - p1.y) * lerpFactor };
        }
        ctx.fillStyle = (id == 0) ? "#3498db" : "#f1c40f";
        ctx.beginPath();
        ctx.arc(centerX + (p.x/1000) * renderScale, centerY + (p.y/1000) * renderScale, (AH_PADDLE_RADIUS/1000) * renderScale, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = "#fff"; ctx.lineWidth = 2; ctx.stroke();
    }

    let puck = localState.puck;
    if (puck) {
        if (currentServerState && lastServerState && lastServerState.puck && currentServerState.puck) {
            const p1 = lastServerState.puck, p2 = currentServerState.puck;
            puck = { x: p1.x + (p2.x - p1.x) * lerpFactor, y: p1.y + (p2.y - p1.y) * lerpFactor };
        }
        ctx.fillStyle = "#ecf0f1";
        ctx.beginPath();
        ctx.arc(centerX + (puck.x/1000) * renderScale, centerY + (puck.y/1000) * renderScale, (AH_PUCK_RADIUS/1000) * renderScale, 0, Math.PI * 2);
        ctx.fill();
    }

    ctx.fillStyle = "#fff"; ctx.font = "bold 32px monospace"; ctx.textAlign = "center";
    const s0 = (localState.players[0] && localState.players[0].sc) || 0;
    const s1 = (localState.players[1] && localState.players[1].sc) || 0;
    ctx.fillText(`${s0} : ${s1}`, centerX, 40);
    ctx.font = "14px monospace";
    ctx.fillText(`Status: ${localState.status}`, centerX, canvas.height - 20);
}
