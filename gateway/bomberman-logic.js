/**
 * Bomberman-Specific Game Logic
 * Ported from src/bomberman.lisp, src/bombs.lisp
 */

const PLAYER_SIZE = 0.7;
const HALF_SIZE = PLAYER_SIZE / 2.0;
const BOMB_TIMER = 180;
const BOMB_RADIUS = 3;
const EXPLOSION_DURATION = 30;

const COLORS = ["#3498db", "#e74c3c", "#2ecc71", "#f1c40f", "#9b59b6", "#1abc9c", "#e67e22"];

/**
 * Returns the tile value at (x, y). Default is 1 (wall) if out of bounds.
 */
function getTile(level, x, y) {
    const ix = Math.floor(x + 0.5);
    const iy = Math.floor(y + 0.5);
    if (level && iy >= 0 && iy < level.length && ix >= 0 && ix < level[iy].length) {
        return level[iy][ix];
    }
    return 1; // Default to wall
}

/**
 * Returns a set of bomb IDs (e.g., "5,5") that overlap the player at (x, y).
 */
function getOverlappingBombs(x, y, bombs) {
    const h = HALF_SIZE;
    const ids = new Set();
    const offsets = [-h, h];
    for (let ox of offsets) {
        for (let oy of offsets) {
            const bx = Math.floor((x + ox) + 0.5);
            const by = Math.floor((y + oy) + 0.5);
            const bid = `${bx},${by}`;
            if (bombs && bombs[bid]) {
                ids.add(bid);
            }
        }
    }
    return ids;
}

/**
 * Check collision with other living players.
 */
function collidesWithPlayer(x, y, pid, players) {
    if (!players) return false;
    for (let otherId in players) {
        if (otherId == pid) continue;
        const other = players[otherId];
        if (other.h <= 0) continue;
        if (Math.abs(x - other.x) < PLAYER_SIZE && Math.abs(y - other.y) < PLAYER_SIZE) {
            return true;
        }
    }
    return false;
}

/**
 * Full collision check for Bomberman: Tiles, Bombs (unless allowed), and Players.
 */
function bombermanCollides(x, y, pid, state, allowedBombIds) {
    const custom = state.customState || {};
    const level = custom.level || [];
    const bombs = custom.bombs || {};
    const h = HALF_SIZE;
    const offsets = [[-h, -h], [h, -h], [-h, h], [h, h]];

    for (let [ox, oy] of offsets) {
        const px = x + ox;
        const py = y + oy;
        const tile = getTile(level, px, py);
        const bx = Math.floor(px + 0.5);
        const by = Math.floor(py + 0.5);
        const bid = `${bx},${by}`;

        if (tile !== 0 || (bombs[bid] && !allowedBombIds.has(bid))) {
            return true;
        }
    }
    return collidesWithPlayer(x, y, pid, state.players);
}

/**
 * Move-and-slide specifically for Bomberman's player movement.
 */
function bombermanMoveAndSlide(pid, player, input, state) {
    if (player.h <= 0) return player;

    const dx = input.dx || 0;
    const dy = input.dy || 0;
    const bombs = (state.customState && state.customState.bombs) || {};
    const allowedBombIds = getOverlappingBombs(player.x, player.y, bombs);

    let finalX = player.x;
    let finalY = player.y;

    if (!bombermanCollides(player.x + dx, player.y, pid, state, allowedBombIds)) {
        finalX = player.x + dx;
    }

    if (!bombermanCollides(finalX, player.y + dy, pid, state, allowedBombIds)) {
        finalY = player.y + dy;
    }

    return { ...player, x: finalX, y: finalY };
}

/**
 * Deterministic PRNG: matches fb-next-rand in Lisp
 */
function fbNextRand(seed) {
    const newSeed = (seed * 1103515245 + 12345) % 2147483648;
    const val = newSeed / 2147483648.0;
    return [newSeed, val];
}

function fbRandInt(seed, max) {
    const [newSeed, val] = fbNextRand(seed);
    return [newSeed, Math.floor(val * max)];
}

/**
 * Ported bomb spawning logic
 */
function spawnBomb(player, customState) {
    const bx = Math.floor(player.x + 0.5);
    const by = Math.floor(player.y + 0.5);
    const bid = `${bx},${by}`;
    
    let bombs = { ...(customState.bombs || {}) };
    if (!bombs[bid]) {
        bombs[bid] = { x: bx, y: by, tm: BOMB_TIMER };
    }
    return { ...customState, bombs };
}

/**
 * Ported bomb update logic (simplified timers for prediction)
 */
function updateBombs(state, inputs) {
    let custom = { ...state.customState };
    let bombs = { ...(custom.bombs || {}) };
    
    // 1. Process new bomb placements
    for (let pid in state.players) {
        const input = (inputs && inputs[pid]) || {};
        if (input['drop-bomb']) {
            custom = spawnBomb(state.players[pid], custom);
            bombs = custom.bombs;
        }
    }

    // 2. Tick existing bombs
    let nextBombs = {};
    for (let bid in bombs) {
        let b = { ...bombs[bid] };
        b.tm -= 1;
        if (b.tm > 0) {
            nextBombs[bid] = b;
        }
    }
    
    return { ...custom, bombs: nextBombs };
}

/**
 * Ported bot logic from bots.lisp
 */
function updateBots(state) {
    const custom = state.customState || {};
    let seed = custom.seed || 0;
    const bots = custom.bots || {};
    const level = custom.level || [];
    const players = state.players || {};
    
    let nextBots = {};
    let nextPlayers = { ...players };

    for (let bid in bots) {
        const bot = bots[bid];
        let x = bot.x;
        let y = bot.y;
        let dx = bot.dx;
        let dy = bot.dy;
        
        let nx = x + dx;
        let ny = y + dy;

        // Simple wall bounce
        if (getTile(level, nx, ny) !== 0) {
            let [newSeed, dir] = fbRandInt(seed, 4);
            seed = newSeed;
            switch(dir) {
                case 0: dx = 0.025; dy = 0.0; break;
                case 1: dx = -0.025; dy = 0.0; break;
                case 2: dx = 0.0; dy = 0.025; break;
                case 3: dx = 0.0; dy = -0.025; break;
            }
            nx = x; ny = y;
        }

        nextBots[bid] = { ...bot, x: nx, y: ny, dx, dy };

        // Kill players
        for (let pid in nextPlayers) {
            const p = nextPlayers[pid];
            if (p.h > 0 && Math.abs(nx - p.x) < 0.6 && Math.abs(ny - p.y) < 0.6) {
                nextPlayers[pid] = { ...p, h: 0 };
            }
        }
    }

    return {
        ...state,
        players: nextPlayers,
        customState: { ...custom, bots: nextBots, seed: seed }
    };
}

/**
 * Entry point for a single tick of the Bomberman simulation.
 */
function bombermanUpdate(state, inputs) {
    let nextTick = state.tick + 1;
    
    let customAfterBombs = updateBombs(state, inputs);
    let stateAfterBombs = { ...state, customState: customAfterBombs };

    let nextPlayers = { ...state.players };
    for (let pid in nextPlayers) {
        const input = (inputs && inputs[pid]) || {};
        nextPlayers[pid] = bombermanMoveAndSlide(pid, nextPlayers[pid], input, stateAfterBombs);
    }

    let stateAfterBots = updateBots({ ...stateAfterBombs, players: nextPlayers, tick: nextTick });

    return {
        tick: nextTick,
        players: stateAfterBots.players,
        customState: stateAfterBots.customState
    };
}

/**
 * Apply delta to a base state.
 */
function bombermanApplyDelta(baseState, delta) {
    const newState = JSON.parse(JSON.stringify(baseState));
    newState.tick = delta.t;
    
    if (delta.p) {
        delta.p.forEach(dp => { 
            newState.players[dp.id] = dp;
        });
    }
    if (delta.l) newState.customState.level = delta.l;
    if (delta.s !== undefined) newState.customState.seed = delta.s;
    
    newState.customState.bombs = {};
    if (delta.b) {
        delta.b.forEach(b => { newState.customState.bombs[`${b.x},${b.y}`] = b; });
    }
    newState.customState.explosions = delta.e || [];
    newState.customState.bots = delta.bots || [];
    
    return newState;
}

/**
 * Sync entities we don't predict.
 */
function bombermanSync(localState, serverState, myPlayerId) {
    for (let id in serverState.players) {
        if (id != myPlayerId) {
            localState.players[id] = serverState.players[id];
        } else if (localState.players[id]) {
            localState.players[id].h = serverState.players[id].h;
        } else {
            localState.players[id] = serverState.players[id];
        }
    }
    localState.customState.explosions = serverState.customState.explosions;
    if (serverState.customState.level.length > 0) {
        localState.customState.level = serverState.customState.level;
    }
    localState.customState.bots = serverState.customState.bots;
}

/**
 * Render the game to a canvas.
 */
function bombermanRender(ctx, canvas, localState, TILE_SIZE) {
    const custom = localState.customState;
    if (!custom || !custom.level || custom.level.length === 0) return;
    
    if (canvas.width !== custom.level[0].length * TILE_SIZE) {
        canvas.width = custom.level[0].length * TILE_SIZE;
        canvas.height = custom.level.length * TILE_SIZE;
    }

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    
    custom.level.forEach((row, y) => {
        row.forEach((tile, x) => {
            if (tile === 1) {
                ctx.fillStyle = "#444"; 
                ctx.fillRect(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE);
            } else if (tile === 2) {
                ctx.fillStyle = "#8b4513"; 
                ctx.fillRect(x * TILE_SIZE + 1, y * TILE_SIZE + 1, TILE_SIZE - 2, TILE_SIZE - 2);
            }
        });
    });

    ctx.fillStyle = "rgba(255, 69, 0, 0.7)";
    (custom.explosions || []).forEach(exp => {
        ctx.fillRect(exp.x * TILE_SIZE, exp.y * TILE_SIZE, TILE_SIZE, TILE_SIZE);
    });

    const bombs = custom.bombs || {};
    Object.values(bombs).forEach(bomb => {
        ctx.fillStyle = "#333";
        ctx.beginPath();
        ctx.arc(bomb.x * TILE_SIZE + TILE_SIZE/2, bomb.y * TILE_SIZE + TILE_SIZE/2, TILE_SIZE/2.5, 0, Math.PI*2);
        ctx.fill();
        ctx.fillStyle = "#fff";
        ctx.fillRect(bomb.x * TILE_SIZE + 4, bomb.y * TILE_SIZE + 4, (bomb.tm/180)*(TILE_SIZE-8), 2);
    });

    ctx.fillStyle = "#ff00ff"; 
    (custom.bots || []).forEach(bot => {
        ctx.fillRect(bot.x * TILE_SIZE + 4, bot.y * TILE_SIZE + 4, TILE_SIZE - 8, TILE_SIZE - 8);
    });

    Object.values(localState.players).forEach(p => {
        const isDead = p.h <= 0;
        ctx.fillStyle = isDead ? "#555" : COLORS[p.id % COLORS.length];
        ctx.fillRect(p.x * TILE_SIZE + 2, p.y * TILE_SIZE + 2, TILE_SIZE - 4, TILE_SIZE - 4);
        if (isDead) {
            ctx.fillStyle = "#fff";
            ctx.font = "10px Arial";
            ctx.fillText("X", p.x * TILE_SIZE + 6, p.y * TILE_SIZE + 14);
        }
    });
}

// Support Node.js/CommonJS environment for testing
if (typeof module !== 'undefined') {
    module.exports = {
        bombermanUpdate,
        bombermanApplyDelta,
        bombermanSync,
        bombermanRender
    };
}
