import { createGameClient } from '../game-client.js';
import { fpRound } from '../fixed-point.js';
import { airhockeyUpdate, airhockeyApplyDelta, airhockeySync, airhockeyRender } from './logic.js';

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

function resize() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
}
window.addEventListener('resize', resize);
resize();

let mouseX = 0, mouseY = 0;
canvas.addEventListener('mousemove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;
});

const { world } = createGameClient({
    gameName: 'airhockey',
    updateFn: airhockeyUpdate,
    applyDeltaFn: airhockeyApplyDelta,
    syncFn: airhockeySync,
    render: () => airhockeyRender(ctx, canvas, world.localState, 0, world.myPlayerId, world.msPerTick),
    getInput: () => {
        if (world.localState.status !== 'ACTIVE') return null;
        const centerX = canvas.width / 2;
        const centerY = canvas.height / 2;
        const margin = 1.1;
        const unitsW = (8000 / 1000) * margin;
        const unitsH = (12000 / 1000) * margin;
        const renderScale = Math.min(canvas.width / unitsW, canvas.height / unitsH);
        const tx = fpRound(((mouseX - centerX) / renderScale) * 1000);
        const ty = fpRound(((mouseY - centerY) / renderScale) * 1000);
        return { local: { tx, ty }, wire: { TARGET_X: tx, TARGET_Y: ty } };
    },
});

world.reconciliationThresholdSq = 1;
world.comparisonFn = (predicted, authoritative) => {
    const myP = predicted.players[world.myPlayerId];
    const myA = authoritative.players[world.myPlayerId];
    if (!myP || !myA) return false;
    const dx = myP.x - myA.x;
    const dy = myP.y - myA.y;
    if (dx * dx + dy * dy > world.reconciliationThresholdSq) return false;
    const pPuck = predicted.puck, aPuck = authoritative.puck;
    if (!!pPuck !== !!aPuck) return false;
    if (pPuck && aPuck) {
        const dpx = pPuck.x - aPuck.x;
        const dpy = pPuck.y - aPuck.y;
        if (dpx * dpx + dpy * dpy > world.reconciliationThresholdSq) return false;
    }
    return true;
};
