import { createGameClient } from '../game-client.js';

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

function resize() {
    const size = Math.min(window.innerWidth, window.innerHeight - 40);
    canvas.width = size;
    canvas.height = size;
}
window.addEventListener('resize', resize);
resize();

// Pending move: set by click, consumed by getInput
let pendingCell = null;

canvas.addEventListener('click', (e) => {
    if (!world || world.localState.status !== 'ACTIVE') {
        // Allow rematch click on game-over states
        if (world && (world.localState.status === 'X_WINS' ||
                      world.localState.status === 'O_WINS' ||
                      world.localState.status === 'DRAW')) {
            pendingCell = { rematch: true };
        }
        return;
    }
    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const cellSize = canvas.width / 3;
    const col = Math.floor(x / cellSize);
    const row = Math.floor(y / cellSize);
    if (col >= 0 && col < 3 && row >= 0 && row < 3) {
        pendingCell = row * 3 + col;
    }
});

function tttApplyDelta(baseState, delta) {
    return {
        tick: delta.TICK ?? baseState.tick,
        status: delta.STATUS ?? baseState.status,
        turn: delta.TURN ?? baseState.turn,
        board: delta.BOARD ?? baseState.board ?? [null,null,null,null,null,null,null,null,null],
        players: delta.PLAYERS
            ? Object.fromEntries(delta.PLAYERS.map(p => [p.ID, { id: p.ID, side: p.SIDE }]))
            : baseState.players,
    };
}

function tttSync(localState, serverState, _myPlayerId) {
    // Authoritative-only: overwrite everything from server
    localState.tick = serverState.tick;
    localState.status = serverState.status;
    localState.turn = serverState.turn;
    localState.board = serverState.board;
    localState.players = serverState.players;
}

function tttRender(ctx, canvas, state, myPlayerId) {
    const w = canvas.width;
    const h = canvas.height;
    const cellW = w / 3;
    const cellH = h / 3;
    const board = state.board || [];
    const status = state.status || 'WAITING';
    const turn = state.turn ?? 0;

    ctx.clearRect(0, 0, w, h);

    // Find my side
    const me = state.players?.[myPlayerId];
    const mySide = me?.side;

    // Draw grid lines
    ctx.strokeStyle = '#444';
    ctx.lineWidth = 3;
    for (let i = 1; i < 3; i++) {
        ctx.beginPath();
        ctx.moveTo(i * cellW, 0);
        ctx.lineTo(i * cellW, h);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(0, i * cellH);
        ctx.lineTo(w, i * cellH);
        ctx.stroke();
    }

    // Draw X and O
    const pad = cellW * 0.2;
    for (let i = 0; i < 9; i++) {
        const v = board[i];
        if (v === null || v === undefined) continue;
        const col = i % 3;
        const row = Math.floor(i / 3);
        const cx = col * cellW + cellW / 2;
        const cy = row * cellH + cellH / 2;
        const r = cellW / 2 - pad;

        if (v === 0) {
            // X
            ctx.strokeStyle = '#e74c3c';
            ctx.lineWidth = 6;
            ctx.beginPath();
            ctx.moveTo(cx - r, cy - r);
            ctx.lineTo(cx + r, cy + r);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(cx + r, cy - r);
            ctx.lineTo(cx - r, cy + r);
            ctx.stroke();
        } else {
            // O
            ctx.strokeStyle = '#3498db';
            ctx.lineWidth = 6;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.stroke();
        }
    }

    // Status text
    ctx.fillStyle = '#fff';
    ctx.font = `${Math.floor(cellW * 0.15)}px monospace`;
    ctx.textAlign = 'center';

    let msg = '';
    if (status === 'WAITING') {
        msg = 'Waiting for opponent...';
    } else if (status === 'ACTIVE') {
        const turnLabel = turn === 0 ? 'X' : 'O';
        if (mySide === turn) {
            msg = `Your turn (${turnLabel})`;
        } else {
            msg = `Opponent's turn (${turnLabel})`;
        }
    } else if (status === 'X_WINS') {
        msg = mySide === 0 ? 'You win! (click for rematch)' : 'You lose! (click for rematch)';
    } else if (status === 'O_WINS') {
        msg = mySide === 1 ? 'You win! (click for rematch)' : 'You lose! (click for rematch)';
    } else if (status === 'DRAW') {
        msg = 'Draw! (click for rematch)';
    }
    ctx.fillText(msg, w / 2, h - 20);

    // Side indicator
    if (mySide !== undefined) {
        const sideLabel = mySide === 0 ? 'X' : 'O';
        ctx.fillStyle = '#888';
        ctx.font = `${Math.floor(cellW * 0.1)}px monospace`;
        ctx.fillText(`You are: ${sideLabel}`, w / 2, 30);
    }
}

const { world } = createGameClient({
    gameName: 'tictactoe',
    prediction: false,
    applyDeltaFn: tttApplyDelta,
    syncFn: tttSync,
    render: () => tttRender(ctx, canvas, world.localState, world.myPlayerId),
    getInput: () => {
        if (pendingCell === null) return null;
        const cell = pendingCell;
        pendingCell = null;
        if (typeof cell === 'object' && cell.rematch) {
            return { wire: { TYPE: 'REMATCH' } };
        }
        return { wire: { CELL: cell } };
    },
});
