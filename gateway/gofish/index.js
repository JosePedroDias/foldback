import { createGameClient } from '../game-client.js';

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

function resize() {
    canvas.width = Math.min(window.innerWidth, 900);
    canvas.height = Math.min(window.innerHeight - 40, 700);
}
window.addEventListener('resize', resize);
resize();

// Pending action: set by click, consumed by getInput
let pendingAction = null;

// UI state for two-step ask: first pick rank from own hand, then pick target player
let selectedRank = null;

const RANK_NAMES = ['', 'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
const SUIT_SYMBOLS = ['\u2660', '\u2665', '\u2666', '\u2663']; // spade, heart, diamond, club
const SUIT_COLORS = ['#222', '#e74c3c', '#e74c3c', '#222'];

// Flash highlight state: tracks which ranks to highlight and when
// rank=null means flash entire hand
let flashState = null; // { rank, color, startTime, durationMs }
let prevLastAsk = null; // track lastAsk changes

const FLASH_DURATION = 1500;
const FLASH_GREEN = '#2ecc71';
const FLASH_RED = '#e74c3c';

function updateFlash(state, mySeat) {
    const ask = state.lastAsk;

    // Detect lastAsk change
    if (ask && ask !== prevLastAsk &&
        (!prevLastAsk ||
         ask.SEAT !== prevLastAsk.SEAT ||
         ask.TARGET !== prevLastAsk.TARGET ||
         ask.RANK !== prevLastAsk.RANK ||
         ask.GOT !== prevLastAsk.GOT)) {

        if (ask.GOT > 0 && ask.SEAT === mySeat) {
            // I received cards
            flashState = { rank: ask.RANK, color: FLASH_GREEN, startTime: Date.now(), durationMs: FLASH_DURATION };
        } else if (ask.GOT > 0 && ask.TARGET === mySeat) {
            // I lost cards
            flashState = { rank: ask.RANK, color: FLASH_RED, startTime: Date.now(), durationMs: FLASH_DURATION };
        } else if (ask.GOT === 0 && ask.SEAT === mySeat) {
            // I Go Fished — drew a card (flash whole hand since we don't know drawn rank)
            flashState = { rank: null, color: ask.DREW_MATCH ? FLASH_GREEN : '#f39c12', startTime: Date.now(), durationMs: FLASH_DURATION };
        } else {
            flashState = null;
        }
    }
    prevLastAsk = ask;

    // Expire flash
    if (flashState && Date.now() - flashState.startTime > flashState.durationMs) {
        flashState = null;
    }
}

function getFlashAlpha() {
    if (!flashState) return 0;
    const elapsed = Date.now() - flashState.startTime;
    const t = elapsed / flashState.durationMs;
    // Pulse: fade out
    return Math.max(0, 1 - t);
}

function gfApplyDelta(baseState, delta) {
    return {
        tick: delta.TICK ?? baseState.tick,
        status: delta.STATUS ?? baseState.status,
        turn: delta.TURN ?? baseState.turn,
        deckCount: delta.DECK_COUNT ?? baseState.deckCount ?? 0,
        hands: delta.HANDS ?? baseState.hands ?? {},
        books: delta.BOOKS ?? baseState.books ?? {},
        lastAsk: delta.LAST_ASK !== undefined ? delta.LAST_ASK : baseState.lastAsk,
        players: delta.PLAYERS
            ? Object.fromEntries(delta.PLAYERS.map(p => [p.ID, { id: p.ID, seat: p.SEAT, ready: p.READY }]))
            : baseState.players,
    };
}

function gfSync(localState, serverState, _myPlayerId) {
    localState.tick = serverState.tick;
    localState.status = serverState.status;
    localState.turn = serverState.turn;
    localState.deckCount = serverState.deckCount;
    localState.hands = serverState.hands;
    localState.books = serverState.books;
    localState.lastAsk = serverState.lastAsk;
    localState.players = serverState.players;
}

// Layout helpers
function getMyHand(state, mySeat) {
    if (mySeat === null || mySeat === undefined) return [];
    const hand = state.hands?.[mySeat];
    if (!Array.isArray(hand)) return [];
    return [...hand].sort((a, b) => a.RANK - b.RANK || a.SUIT - b.SUIT);
}

function getNumPlayers(state) {
    return Object.keys(state.players || {}).length;
}

function getSeatForPlayer(state, playerId) {
    const p = state.players?.[playerId];
    return p?.seat ?? null;
}

function getAllSeats(state) {
    return Object.values(state.players || {}).map(p => p.seat).sort((a, b) => a - b);
}

function getUniqueRanks(hand) {
    const ranks = new Set(hand.map(c => c.RANK));
    return [...ranks].sort((a, b) => a - b);
}

// Hit-test regions stored each frame
let cardRegions = []; // { x, y, w, h, rank }
let playerRegions = []; // { x, y, w, h, seat }
let readyButtonRegion = null; // { x, y, w, h }
let rematchRegion = null;

canvas.addEventListener('click', (e) => {
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;

    if (!world) return;
    const state = world.localState;
    const mySeat = getSeatForPlayer(state, world.myPlayerId);
    const numPlayers = getNumPlayers(state);

    // Ready-up button
    if (state.status === 'READY_UP' && readyButtonRegion) {
        const r = readyButtonRegion;
        if (mx >= r.x && mx <= r.x + r.w && my >= r.y && my <= r.y + r.h) {
            pendingAction = { type: 'READY' };
            return;
        }
    }

    // Rematch
    if (state.status === 'GAME_OVER' && rematchRegion) {
        const r = rematchRegion;
        if (mx >= r.x && mx <= r.x + r.w && my >= r.y && my <= r.y + r.h) {
            pendingAction = { type: 'REMATCH' };
            return;
        }
    }

    // Only allow moves during ACTIVE and on our turn
    if (state.status !== 'ACTIVE' || state.turn !== mySeat) return;

    // 2-player shortcut: clicking a card immediately sends the ask
    if (numPlayers === 2) {
        for (const cr of cardRegions) {
            if (mx >= cr.x && mx <= cr.x + cr.w && my >= cr.y && my <= cr.y + cr.h) {
                // Find the actual other seat
                let otherSeat = null;
                for (const p of Object.values(state.players || {})) {
                    if (p.seat !== mySeat) { otherSeat = p.seat; break; }
                }
                if (otherSeat !== null) {
                    pendingAction = { rank: cr.rank, target: otherSeat };
                    selectedRank = null;
                }
                return;
            }
        }
        return;
    }

    // Step 1: select a rank from own hand
    if (selectedRank === null) {
        for (const cr of cardRegions) {
            if (mx >= cr.x && mx <= cr.x + cr.w && my >= cr.y && my <= cr.y + cr.h) {
                selectedRank = cr.rank;
                return;
            }
        }
    } else {
        // Step 2: pick a target player
        // Validate selectedRank is still in hand (server may have changed it)
        const myHand = getMyHand(state, mySeat);
        if (!myHand.some(c => c.RANK === selectedRank)) {
            selectedRank = null;
            return;
        }
        for (const pr of playerRegions) {
            if (mx >= pr.x && mx <= pr.x + pr.w && my >= pr.y && my <= pr.y + pr.h) {
                if (pr.seat !== mySeat) {
                    pendingAction = { rank: selectedRank, target: pr.seat };
                    selectedRank = null;
                    return;
                }
            }
        }
        // Clicking a card again changes selection
        for (const cr of cardRegions) {
            if (mx >= cr.x && mx <= cr.x + cr.w && my >= cr.y && my <= cr.y + cr.h) {
                selectedRank = cr.rank;
                return;
            }
        }
        // Click elsewhere: deselect
        selectedRank = null;
    }
});

function drawCard(ctx, x, y, w, h, rank, suit, highlighted, flashColor, flashAlpha) {
    // Card background
    ctx.fillStyle = highlighted ? '#ffffcc' : '#f5f5f0';
    ctx.strokeStyle = highlighted ? '#ff0' : '#888';
    ctx.lineWidth = highlighted ? 3 : 1;
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, 4);
    ctx.fill();
    ctx.stroke();

    // Flash overlay
    if (flashColor && flashAlpha > 0) {
        ctx.save();
        ctx.globalAlpha = flashAlpha * 0.4;
        ctx.fillStyle = flashColor;
        ctx.beginPath();
        ctx.roundRect(x, y, w, h, 4);
        ctx.fill();
        ctx.restore();

        // Flash border
        ctx.save();
        ctx.globalAlpha = flashAlpha;
        ctx.strokeStyle = flashColor;
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.roundRect(x, y, w, h, 4);
        ctx.stroke();
        ctx.restore();
    }

    // Rank + suit
    const label = RANK_NAMES[rank] + SUIT_SYMBOLS[suit];
    ctx.fillStyle = SUIT_COLORS[suit];
    ctx.font = `${Math.floor(h * 0.3)}px monospace`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(label, x + w / 2, y + h / 2);
}

function drawCardBack(ctx, x, y, w, h) {
    ctx.fillStyle = '#2255aa';
    ctx.strokeStyle = '#113377';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, 4);
    ctx.fill();
    ctx.stroke();

    // Pattern
    ctx.strokeStyle = '#3366bb';
    ctx.lineWidth = 0.5;
    const p = 4;
    for (let i = x + p; i < x + w - p; i += 4) {
        ctx.beginPath();
        ctx.moveTo(i, y + p);
        ctx.lineTo(i, y + h - p);
        ctx.stroke();
    }
}

function gfRender(ctx, canvas, state, myPlayerId) {
    const w = canvas.width;
    const h = canvas.height;
    const status = state.status || 'WAITING';
    const turn = state.turn ?? 0;
    const mySeat = getSeatForPlayer(state, myPlayerId);
    const numPlayers = getNumPlayers(state);
    const myHand = getMyHand(state, mySeat);

    // Clear stale selection: not my turn or rank no longer in hand
    if (selectedRank !== null) {
        if (status !== 'ACTIVE' || turn !== mySeat ||
            !myHand.some(c => c.RANK === selectedRank)) {
            selectedRank = null;
        }
    }

    // Update flash state
    updateFlash(state, mySeat);

    ctx.clearRect(0, 0, w, h);
    cardRegions = [];
    playerRegions = [];
    readyButtonRegion = null;
    rematchRegion = null;

    // Background
    ctx.fillStyle = '#0a3d0a';
    ctx.fillRect(0, 0, w, h);

    if (status === 'WAITING') {
        ctx.fillStyle = '#fff';
        ctx.font = '24px monospace';
        ctx.textAlign = 'center';
        ctx.fillText('Waiting for players... (need 2-5)', w / 2, h / 2);
        ctx.font = '16px monospace';
        ctx.fillText(`${numPlayers} player(s) connected`, w / 2, h / 2 + 30);
        return;
    }

    if (status === 'READY_UP') {
        ctx.fillStyle = '#fff';
        ctx.font = '24px monospace';
        ctx.textAlign = 'center';
        ctx.fillText(`${numPlayers} players connected`, w / 2, h / 2 - 60);

        // Show ready status for each player
        let y = h / 2 - 20;
        for (const [pid, p] of Object.entries(state.players || {})) {
            const isMe = parseInt(pid) === myPlayerId;
            const label = isMe ? `Player ${p.seat} (you)` : `Player ${p.seat}`;
            const readyLabel = p.ready ? ' READY' : ' ...';
            ctx.fillStyle = p.ready ? '#2ecc71' : '#888';
            ctx.font = '18px monospace';
            ctx.fillText(label + readyLabel, w / 2, y);
            y += 25;
        }

        // Ready button (if not ready)
        const me = state.players?.[myPlayerId];
        if (me && !me.ready) {
            const bw = 200, bh = 50;
            const bx = w / 2 - bw / 2, by = h / 2 + 80;
            ctx.fillStyle = '#27ae60';
            ctx.beginPath();
            ctx.roundRect(bx, by, bw, bh, 8);
            ctx.fill();
            ctx.fillStyle = '#fff';
            ctx.font = 'bold 20px monospace';
            ctx.fillText('READY', w / 2, by + bh / 2 + 7);
            readyButtonRegion = { x: bx, y: by, w: bw, h: bh };
        }
        return;
    }

    // --- ACTIVE or GAME_OVER ---

    const cardW = 50, cardH = 70;
    const miniCardW = 30, miniCardH = 40;

    // Draw other players across the top
    const allSeats = getAllSeats(state);
    const otherSeats = allSeats.filter(s => s !== mySeat);

    const topY = 50;
    const spacing = w / (otherSeats.length + 1);
    otherSeats.forEach((seat, i) => {
        const cx = spacing * (i + 1);
        const handCount = typeof state.hands?.[seat] === 'number' ? state.hands[seat] : 0;
        const books = state.books?.[seat] || [];
        const isCurrentTurn = status === 'ACTIVE' && turn === seat;

        // Flash indicator for other players (they lost/gained cards)
        let otherFlash = null;
        if (flashState && state.lastAsk) {
            const ask = state.lastAsk;
            if (ask.GOT > 0 && ask.TARGET === seat) {
                otherFlash = { color: FLASH_RED, alpha: getFlashAlpha() };
            } else if (ask.GOT > 0 && ask.SEAT === seat) {
                otherFlash = { color: FLASH_GREEN, alpha: getFlashAlpha() };
            }
        }

        // Player label
        ctx.fillStyle = isCurrentTurn ? '#f1c40f' : '#fff';
        ctx.font = `${isCurrentTurn ? 'bold ' : ''}16px monospace`;
        ctx.textAlign = 'center';
        ctx.fillText(`Player ${seat}`, cx, topY - 5);

        // Card backs
        const totalWidth = Math.min(handCount * 12, 100);
        const startX = cx - totalWidth / 2;
        for (let c = 0; c < handCount; c++) {
            drawCardBack(ctx, startX + c * 12, topY, miniCardW, miniCardH);
        }

        // Flash overlay on other player's area
        if (otherFlash && otherFlash.alpha > 0) {
            const regionW = Math.max(totalWidth + miniCardW, 80);
            ctx.save();
            ctx.globalAlpha = otherFlash.alpha * 0.3;
            ctx.fillStyle = otherFlash.color;
            ctx.fillRect(cx - regionW / 2, topY - 5, regionW, miniCardH + 10);
            ctx.restore();
        }

        if (handCount === 0) {
            ctx.fillStyle = '#666';
            ctx.font = '12px monospace';
            ctx.fillText('(empty)', cx, topY + 20);
        }

        // Books
        if (books.length > 0) {
            ctx.fillStyle = '#2ecc71';
            ctx.font = '12px monospace';
            ctx.fillText(`Books: ${books.map(r => RANK_NAMES[r]).join(' ')}`, cx, topY + miniCardH + 15);
        }

        // Hit region for targeting
        const regionW = Math.max(totalWidth + miniCardW, 80);
        const regionH = miniCardH + 30;
        playerRegions.push({
            x: cx - regionW / 2, y: topY - 20,
            w: regionW, h: regionH,
            seat,
        });

        // Highlight if selecting target
        if (selectedRank !== null && seat !== mySeat) {
            ctx.strokeStyle = '#f39c12';
            ctx.lineWidth = 2;
            ctx.setLineDash([4, 4]);
            ctx.strokeRect(cx - regionW / 2, topY - 20, regionW, regionH);
            ctx.setLineDash([]);
        }
    });

    // Deck count (center)
    const deckY = h / 2 - 60;
    ctx.fillStyle = '#ccc';
    ctx.font = '14px monospace';
    ctx.textAlign = 'center';
    ctx.fillText(`Deck: ${state.deckCount} cards`, w / 2, deckY);
    if (state.deckCount > 0) {
        drawCardBack(ctx, w / 2 - miniCardW / 2, deckY + 5, miniCardW, miniCardH);
    }

    // Last ask message
    const ask = state.lastAsk;
    if (ask) {
        const msgY = h / 2 + 10;
        ctx.font = '16px monospace';
        ctx.textAlign = 'center';
        if (ask.GOT > 0) {
            ctx.fillStyle = '#2ecc71';
            const who = ask.SEAT === mySeat ? 'You' : `Player ${ask.SEAT}`;
            const whom = ask.TARGET === mySeat ? 'you' : `Player ${ask.TARGET}`;
            ctx.fillText(
                `${who} asked ${whom} for ${RANK_NAMES[ask.RANK]}s — got ${ask.GOT}!`,
                w / 2, msgY
            );
        } else {
            ctx.fillStyle = '#e74c3c';
            const who = ask.SEAT === mySeat ? 'You' : `Player ${ask.SEAT}`;
            const whom = ask.TARGET === mySeat ? 'you' : `Player ${ask.TARGET}`;
            let msg = `${who} asked ${whom} for ${RANK_NAMES[ask.RANK]}s — Go Fish!`;
            if (ask.DREW_MATCH === true) {
                msg += ' (drew a match, goes again!)';
            }
            ctx.fillText(msg, w / 2, msgY);
        }
    }

    // Turn indicator
    const turnY = h / 2 + 40;
    ctx.font = '18px monospace';
    ctx.textAlign = 'center';
    if (status === 'ACTIVE') {
        if (turn === mySeat) {
            ctx.fillStyle = '#f1c40f';
            if (numPlayers === 2) {
                ctx.fillText('Your turn! Click a card to ask for', w / 2, turnY);
            } else if (selectedRank !== null) {
                ctx.fillText(`Asking for ${RANK_NAMES[selectedRank]}s — click a player above`, w / 2, turnY);
            } else {
                ctx.fillText('Your turn! Click a card to ask for', w / 2, turnY);
            }
        } else {
            ctx.fillStyle = '#aaa';
            ctx.fillText(`Player ${turn}'s turn...`, w / 2, turnY);
        }
    }

    // My hand at the bottom
    const handY = h - cardH - 60;
    const myBooks = state.books?.[mySeat] || [];

    // My label
    ctx.fillStyle = (status === 'ACTIVE' && turn === mySeat) ? '#f1c40f' : '#fff';
    ctx.font = `${(status === 'ACTIVE' && turn === mySeat) ? 'bold ' : ''}16px monospace`;
    ctx.textAlign = 'center';
    ctx.fillText(`You (Player ${mySeat})`, w / 2, handY - 10);

    // My books
    if (myBooks.length > 0) {
        ctx.fillStyle = '#2ecc71';
        ctx.font = '12px monospace';
        ctx.fillText(`Books: ${myBooks.map(r => RANK_NAMES[r]).join(' ')}`, w / 2, h - 15);
    }

    // Flash info for own hand
    const flashAlpha = getFlashAlpha();
    const flashRank = flashState?.rank;
    const flashColor = flashState?.color;

    // Draw my cards
    if (myHand.length > 0) {
        const totalWidth = myHand.length * (cardW + 5) - 5;
        const startX = w / 2 - totalWidth / 2;

        myHand.forEach((card, i) => {
            const cx = startX + i * (cardW + 5);
            const highlighted = selectedRank === card.RANK;
            const rankMatch = flashRank === null || card.RANK === flashRank;
            const cardFlashColor = rankMatch ? flashColor : null;
            const cardFlashAlpha = rankMatch ? flashAlpha : 0;
            drawCard(ctx, cx, handY, cardW, cardH, card.RANK, card.SUIT, highlighted, cardFlashColor, cardFlashAlpha);
            cardRegions.push({ x: cx, y: handY, w: cardW, h: cardH, rank: card.RANK });
        });
    } else {
        ctx.fillStyle = '#666';
        ctx.font = '14px monospace';
        ctx.fillText('(no cards)', w / 2, handY + cardH / 2);
    }

    // Game over
    if (status === 'GAME_OVER') {
        // Find winner (most books)
        let maxBooks = -1;
        let winner = -1;
        for (const s of allSeats) {
            const bk = state.books?.[s]?.length || 0;
            if (bk > maxBooks) {
                maxBooks = bk;
                winner = s;
            }
        }

        ctx.fillStyle = 'rgba(0,0,0,0.7)';
        ctx.fillRect(0, h / 2 - 80, w, 160);

        ctx.fillStyle = '#f1c40f';
        ctx.font = 'bold 28px monospace';
        ctx.textAlign = 'center';
        if (winner === mySeat) {
            ctx.fillText('You win!', w / 2, h / 2 - 30);
        } else {
            ctx.fillText(`Player ${winner} wins!`, w / 2, h / 2 - 30);
        }

        // Show final book counts
        ctx.font = '16px monospace';
        ctx.fillStyle = '#fff';
        let scores = [];
        for (const s of allSeats) {
            const bk = state.books?.[s]?.length || 0;
            scores.push(`P${s}: ${bk}`);
        }
        ctx.fillText(`Books — ${scores.join('  ')}`, w / 2, h / 2 + 5);

        // Rematch button
        const bw = 250, bh = 40;
        const bx = w / 2 - bw / 2, by = h / 2 + 25;
        ctx.fillStyle = '#27ae60';
        ctx.beginPath();
        ctx.roundRect(bx, by, bw, bh, 8);
        ctx.fill();
        ctx.fillStyle = '#fff';
        ctx.font = 'bold 18px monospace';
        ctx.fillText('Click for rematch', w / 2, by + bh / 2 + 6);
        rematchRegion = { x: bx, y: by, w: bw, h: bh };
    }
}

const { world } = createGameClient({
    gameName: 'gofish',
    prediction: false,
    applyDeltaFn: gfApplyDelta,
    syncFn: gfSync,
    render: () => gfRender(ctx, canvas, world.localState, world.myPlayerId),
    getInput: () => {
        if (pendingAction === null) return null;
        const action = pendingAction;
        pendingAction = null;
        if (action.type === 'READY') {
            return { wire: { TYPE: 'READY' } };
        }
        if (action.type === 'REMATCH') {
            return { wire: { TYPE: 'REMATCH' } };
        }
        return { wire: { RANK: action.rank, TARGET: action.target } };
    },
});
