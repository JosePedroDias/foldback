import { createGameClient } from '../game-client.js';
import { fpRound } from '../fixed-point.js';
import { pongUpdate, pongApplyDelta, pongSync, pongRender } from './logic.js';

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

function resize() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
}
window.addEventListener('resize', resize);
resize();

let mouseY = 0;
canvas.addEventListener('mousemove', (e) => { mouseY = e.clientY; });

const { world } = createGameClient({
    gameName: 'pong',
    updateFn: pongUpdate,
    applyDeltaFn: pongApplyDelta,
    syncFn: pongSync,
    render: () => pongRender(ctx, canvas, world.localState, 0, world.myPlayerId, world.msPerTick),
    getInput: () => {
        if (world.localState.status !== 'ACTIVE') return null;
        const centerY = canvas.height / 2;
        const margin = 1.15;
        const unitsH = (8000 / 1000) * margin;
        const renderScale = Math.min(canvas.width / ((12000 / 1000) * margin), canvas.height / unitsH);
        const ty = fpRound(((mouseY - centerY) / renderScale) * 1000);
        return { local: { ty }, wire: { TARGET_Y: ty } };
    },
});

world.reconciliationThresholdSq = 1;
world.comparisonFn = (predicted, authoritative) => {
    const myP = predicted.players[world.myPlayerId];
    const myA = authoritative.players[world.myPlayerId];
    if (!myP || !myA) return false;
    const dy = myP.y - myA.y;
    if (dy * dy > world.reconciliationThresholdSq) return false;
    const pBall = predicted.ball, aBall = authoritative.ball;
    if (!!pBall !== !!aBall) return false;
    if (pBall && aBall) {
        const dbx = pBall.x - aBall.x;
        const dby = pBall.y - aBall.y;
        if (dbx * dbx + dby * dby > world.reconciliationThresholdSq) return false;
    }
    return true;
};
