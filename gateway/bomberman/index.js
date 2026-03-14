import { createGameClient } from '../game-client.js';
import { bombermanUpdate, bombermanApplyDelta, bombermanSync, bombermanRender } from './logic.js';

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');
const TILE_SIZE = 20;

const isAutoplay = new URLSearchParams(window.location.search).get('autoplay') === '1';
if (isAutoplay) document.getElementById('autoplayMode').style.display = 'block';

const keys = new Set();
window.addEventListener('keydown', (e) => { keys.add(e.key.toLowerCase()); });
window.addEventListener('keyup', (e) => { keys.delete(e.key.toLowerCase()); });

createGameClient({
    gameName: 'bomberman',
    updateFn: bombermanUpdate,
    applyDeltaFn: bombermanApplyDelta,
    syncFn: bombermanSync,
    render: (world) => bombermanRender(ctx, canvas, world.localState, TILE_SIZE, world.myPlayerId),
    getInput: () => {
        let dx = 0, dy = 0, bomb = false;
        if (isAutoplay) {
            if (Math.random() < 0.05) dx = (Math.random() < 0.5 ? -1 : 1);
            if (Math.random() < 0.05) dy = (Math.random() < 0.5 ? -1 : 1);
            if (Math.random() < 0.01) bomb = true;
        } else {
            if (keys.has('arrowleft') || keys.has('a')) dx = -1;
            if (keys.has('arrowright') || keys.has('d')) dx = 1;
            if (keys.has('arrowup') || keys.has('w')) dy = -1;
            if (keys.has('arrowdown') || keys.has('s')) dy = 1;
            if (keys.has(' ') || keys.has('b')) bomb = true;
        }
        return { local: { dx, dy, 'drop-bomb': bomb }, wire: { DX: dx, DY: dy, DROP_BOMB: bomb } };
    },
});
