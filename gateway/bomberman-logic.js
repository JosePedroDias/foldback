/**
 * Bomberman-Specific Game Logic (Fixed-Point Port)
 */

if (typeof require !== 'undefined') {
    const fp = require('./fixed-point.js');
    const physics = require('./physics.js');
    Object.assign(global, fp);
    Object.assign(global, physics);
}

const PLAYER_SIZE = 700;
const HALF_SIZE = 350;
const BOMB_TIMER = 180;
const BOMB_RADIUS = 3;
const EXPLOSION_DURATION = 30;

const COLORS = ["#3498db", "#e74c3c", "#2ecc71", "#f1c40f", "#9b59b6", "#1abc9c", "#e67e22"];

/**
 * Returns the tile value at (x, y). Default is 1 (wall) if out of bounds.
 */
function getTile(level, x, y) {
    const ix = Math.floor(fpToFloat(fpAdd(x, 500)));
    const iy = Math.floor(fpToFloat(fpAdd(y, 500)));
    if (level && iy >= 0 && iy < level.length && ix >= 0 && ix < level[iy].length) {
        return level[iy][ix];
    }
    return 1;
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
            const bx = Math.floor(fpToFloat(fpAdd(fpAdd(x, ox), 500)));
            const by = Math.floor(fpToFloat(fpAdd(fpAdd(y, oy), 500)));
            const bid = `${bx},${by}`;
            if (bombs && bombs[bid]) {
                ids.add(bid);
            }
        }
    }
    return ids;
}

/**
 * Check collision with other living players using shared AABB logic.
 */
function collidesWithPlayer(x, y, pid, players) {
    if (!players) return false;
    for (let otherId in players) {
        if (otherId == pid) continue;
        const other = players[otherId];
        if (other.h <= 0) continue;
        if (fpAABBOverlapP(x, y, PLAYER_SIZE, PLAYER_SIZE, other.x, other.y, PLAYER_SIZE, PLAYER_SIZE)) {
            return true;
        }
    }
    return false;
}

/**
 * Full collision check for Bomberman.
 */
function bombermanCollides(x, y, pid, state, allowedBombIds) {
    const custom = state.customState || {};
    const level = custom.level || [];
    const bombs = custom.bombs || {};
    const h = HALF_SIZE;
    const offsets = [[-h, -h], [h, -h], [-h, h], [h, h]];

    for (let [ox, oy] of offsets) {
        const px = fpAdd(x, ox);
        const py = fpAdd(y, oy);
        const tile = getTile(level, px, py);
        const bx = Math.floor(fpToFloat(fpAdd(px, 500)));
        const by = Math.floor(fpToFloat(fpAdd(py, 500)));
        const bid = `${bx},${by}`;

        if (tile !== 0 || (bombs[bid] && !allowedBombIds.has(bid))) {
            return true;
        }
    }
    return collidesWithPlayer(x, y, pid, state.players);
}

/**
 * Move-and-slide for Bomberman (Fixed-Point).
 */
function bombermanMoveAndSlide(pid, player, input, state) {
    if (player.h <= 0) return player;

    const dx = fpFromFloat(input.dx || 0);
    const dy = fpFromFloat(input.dy || 0);
    const bombs = (state.customState && state.customState.bombs) || {};
    const allowedBombIds = getOverlappingBombs(player.x, player.y, bombs);

    let finalX = player.x;
    let finalY = player.y;

    if (!bombermanCollides(fpAdd(player.x, dx), player.y, pid, state, allowedBombIds)) {
        finalX = fpAdd(player.x, dx);
    }

    if (!bombermanCollides(finalX, fpAdd(player.y, dy), pid, state, allowedBombIds)) {
        finalY = fpAdd(player.y, dy);
    }

    return { ...player, x: finalX, y: finalY };
}

/**
 * Ported bomb spawning logic
 */
function spawnBomb(player, customState) {
    const bx = Math.floor(fpToFloat(fpAdd(player.x, 500)));
    const by = Math.floor(fpToFloat(fpAdd(player.y, 500)));
    const bid = `${bx},${by}`;
    
    let bombs = { ...(customState.bombs || {}) };
    if (!bombs[bid]) {
        bombs[bid] = { x: bx, y: by, tm: BOMB_TIMER };
    }
    return { ...customState, bombs };
}

/**
 * Ported bomb update logic (Fixed-Point + Explosion Rays)
 */
function updateBombs(state, inputs) {
    let custom = { ...state.customState };
    let bombs = { ...(custom.bombs || {}) };
    let explosions = {};
    let level = [...(custom.level || [])];
    let players = { ...state.players };
    
    // 1. Process new bomb placements
    for (let pid in players) {
        const input = (inputs && inputs[pid]) || {};
        if (input['drop-bomb']) {
            custom = spawnBomb(players[pid], custom);
            bombs = custom.bombs;
        }
    }

    // 2. Tick existing bombs
    let nextBombs = {};
    for (let bid in bombs) {
        let b = { ...bombs[bid] };
        b.tm -= 1;
        if (b.tm <= 0) {
            // EXPLODE!
            explosions[bid] = EXPLOSION_DURATION;
            const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
            for (let [dx, dy] of dirs) {
                for (let r = 1; r <= BOMB_RADIUS; r++) {
                    const ex = b.x + dx * r;
                    const ey = b.y + dy * r;
                    const tile = getTile(level, fpFromFloat(ex), fpFromFloat(ey));
                    const eid = `${ex},${ey}`;
                    explosions[eid] = EXPLOSION_DURATION;
                    if (tile === 1 || tile === 2) {
                        if (tile === 2) {
                            // Destroy crate
                            level[ey] = [...level[ey]];
                            level[ey][ex] = 0;
                        }
                        break;
                    }
                }
            }
        } else {
            nextBombs[bid] = b;
        }
    }

    // 3. Kill players in explosions
    let nextPlayers = { ...players };
    for (let eid in explosions) {
        const [ex, ey] = eid.split(',').map(Number);
        for (let pid in nextPlayers) {
            const p = nextPlayers[pid];
            if (p.h > 0 && 
                Math.abs(fpFromFloat(ex) - p.x) < 800 && 
                Math.abs(fpFromFloat(ey) - p.y) < 800) {
                nextPlayers[pid] = { ...p, h: 0, dt: state.tick };
            }
        }
    }
    
    return { 
        ...custom, 
        bombs: nextBombs, 
        explosions: Object.keys(explosions).map(eid => {
            const [x, y] = eid.split(',').map(Number);
            return { x, y };
        }),
        level: level,
        players: nextPlayers
    };
}

/**
 * Ported bot logic
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
        
        let nx = fpAdd(x, dx);
        let ny = fpAdd(y, dy);

        // Simple wall bounce
        if (getTile(level, nx, ny) !== 0) {
            let [newSeed, dir] = fbRandInt(seed, 4);
            seed = newSeed;
            switch(dir) {
                case 0: dx = 25; dy = 0; break;
                case 1: dx = -25; dy = 0; break;
                case 2: dx = 0; dy = 25; break;
                case 3: dx = 0; dy = -25; break;
            }
            nx = x; ny = y;
        }

        nextBots[bid] = { ...bot, x: nx, y: ny, dx, dy };

        // Kill players
        for (let pid in nextPlayers) {
            const p = nextPlayers[pid];
            if (p.h > 0 && fpAbs(fpSub(nx, p.x)) < 600 && fpAbs(fpSub(ny, p.y)) < 600) {
                nextPlayers[pid] = { ...p, h: 0, dt: state.tick };
            }
        }
    }

    return {
        ...state,
        players: nextPlayers,
        customState: { ...custom, bots: nextBots, seed: seed }
    };
}

function bombermanUpdate(state, inputs) {
    let nextTick = state.tick + 1;
    
    // updateBombs now returns updated players too because of explosions
    let customAfterBombs = updateBombs(state, inputs);
    let playersAfterExplosions = customAfterBombs.players;
    delete customAfterBombs.players;

    let stateAfterBombs = { ...state, players: playersAfterExplosions, customState: customAfterBombs };

    let nextPlayers = { ...stateAfterBombs.players };
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

function bombermanApplyDelta(baseState, delta) {
    const newState = JSON.parse(JSON.stringify(baseState));
    newState.tick = delta.t;
    if (delta.p) delta.p.forEach(dp => { newState.players[dp.id] = dp; });
    if (delta.l) newState.customState.level = delta.l;
    if (delta.s !== undefined) newState.customState.seed = delta.s;
    if (delta.b) {
        newState.customState.bombs = {};
        delta.b.forEach(b => { newState.customState.bombs[`${b.x},${b.y}`] = b; });
    }
    newState.customState.explosions = delta.e || [];
    if (delta.bots) {
        newState.customState.bots = {};
        delta.bots.forEach((bot, idx) => { newState.customState.bots[idx] = bot; });
    }
    return newState;
}

function bombermanSync(localState, serverState, myPlayerId) {
    for (let id in serverState.players) {
        if (id != myPlayerId) localState.players[id] = serverState.players[id];
        else if (localState.players[id]) localState.players[id].h = serverState.players[id].h;
        else localState.players[id] = serverState.players[id];
    }
    localState.customState.bombs = serverState.customState.bombs;
    localState.customState.explosions = serverState.customState.explosions;
    if (serverState.customState.level.length > 0) localState.customState.level = serverState.customState.level;
    localState.customState.bots = serverState.customState.bots;
}

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

    const bots = custom.bots || {};
    Object.values(bots).forEach(bot => {
        ctx.fillStyle = "#ff00ff"; 
        ctx.fillRect(fpToFloat(bot.x) * TILE_SIZE + 4, fpToFloat(bot.y) * TILE_SIZE + 4, TILE_SIZE - 8, TILE_SIZE - 8);
    });

    Object.values(localState.players).forEach(p => {
        const isDead = p.h <= 0;
        ctx.fillStyle = isDead ? "#555" : COLORS[p.id % COLORS.length];
        ctx.fillRect(fpToFloat(p.x) * TILE_SIZE + 2, fpToFloat(p.y) * TILE_SIZE + 2, TILE_SIZE - 4, TILE_SIZE - 4);
        if (isDead) {
            ctx.fillStyle = "#fff"; ctx.font = "10px Arial";
            ctx.fillText("X", fpToFloat(p.x) * TILE_SIZE + 6, fpToFloat(p.y) * TILE_SIZE + 14);
        }
    });
}

if (typeof module !== 'undefined') {
    module.exports = { bombermanUpdate, bombermanApplyDelta, bombermanSync, bombermanRender };
}
