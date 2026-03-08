import { test, expect } from '@playwright/test';

test('Client identifies a bad prediction and rolls back', async ({ page }) => {
  // 1. Go to the game
  await page.goto('http://localhost:8080/bomberman/?protocol=websockets');

  // 2. Wait until we have a Player ID and are receiving ticks
  await expect(page.locator('#netStats')).toContainText('ID:', { timeout: 15000 });
  await expect(page.locator('#netStats')).toContainText('Tick:', { timeout: 10000 });

  // 3. Record initial rollback count
  const initialRollbacks = await page.evaluate(() => {
    return window['foldbackStats']?.rollbackCount || 0;
  });

  // 4. Move the player so the server has a reason to send an update for them
  await page.keyboard.down('d');
  await page.waitForTimeout(500);
  await page.keyboard.up('d');

  // 5. Intentionally "corrupt" the local state to trigger a misprediction
  // Teleport the player locally to (50000, 50000) in fixed-point
  await page.evaluate(() => {
    const w = window['world'];
    if (w.myPlayerId !== null) {
      const p = w.localState.players[w.myPlayerId];
      if (p) {
        p.x = 50000;
        p.y = 50000;
        // Update current history slot too
        w.history.set(w.localState.tick, JSON.parse(JSON.stringify(w.localState)));
      }
    }
  });

  // 6. Wait for the server to send an update that contradicts our corrupted position
  await expect.poll(async () => {
    const stats = await page.evaluate(() => window['foldbackStats']);
    return stats?.rollbackCount || 0;
  }, {
    message: 'Expected rollback count to increase after state corruption',
    timeout: 15000,
  }).toBeGreaterThan(initialRollbacks);

  // 7. Verify the player is back in a sane position (not 50000, 50000)
  const posAfterRollback = await page.evaluate(() => {
    const p = window['world'].localState.players[window['world'].myPlayerId];
    return { x: p.x, y: p.y };
  });

  expect(posAfterRollback.x).toBeLessThan(20000);
  expect(posAfterRollback.y).toBeLessThan(20000);

  // 8. STABILITY CHECK: Wait a few more frames and ensure we haven't diverged again
  await page.waitForTimeout(500);
  const finalPos = await page.evaluate(() => {
    const p = window['world'].localState.players[window['world'].myPlayerId];
    return { x: p.x, y: p.y };
  });

  const drift = Math.sqrt(Math.pow(finalPos.x - posAfterRollback.x, 2) + Math.pow(finalPos.y - posAfterRollback.y, 2));
  // Player shouldn't have moved much if we aren't pressing keys now
  expect(drift).toBeLessThan(1000);
  expect(finalPos.x).toBeLessThan(20000);
});
