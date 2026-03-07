import { test, expect } from '@playwright/test';

test('Client identifies a bad prediction and rolls back', async ({ page }) => {
  // 1. Go to the game
  await page.goto('http://localhost:8080/bomberman.html?protocol=websockets');

  // 2. Wait until we have a Player ID and are receiving ticks
  await expect(page.locator('#netStats')).toContainText('ID:', { timeout: 15000 });
  
  // Capture console logs to see the misprediction warning
  const logs: string[] = [];
  page.on('console', msg => {
    logs.push(msg.text());
    if (msg.text().includes('MISPREDICTION')) {
        console.log(`[BROWSER LOG FOUND]: ${msg.text()}`);
    }
  });

  // 3. Move the player so the server has a reason to send an update for them
  console.log("Moving player to ensure server broadcast...");
  await page.keyboard.down('d');
  await page.waitForTimeout(500);
  await page.keyboard.up('d');

  // 4. Intentionally "corrupt" the local state to trigger a misprediction
  // We'll teleport the player locally to (50, 50)
  await page.evaluate(() => {
    // @ts-ignore
    const w = world;
    if (w.myPlayerId !== null) {
      const p = w.localState.players[w.myPlayerId];
      if (p) {
        console.log(`CORRUPTING LOCAL STATE: Teleporting from ${p.x},${p.y} to 50,50`);
        p.x = 50.0;
        p.y = 50.0;
        // Update current history slot too
        w.history.set(w.localState.tick, JSON.parse(JSON.stringify(w.localState)));
      }
    }
  });

  // 5. Wait for the server to send an update that contradicts our (50, 50) position
  console.log("Waiting for misprediction detection...");
  await expect.poll(() => logs.some(l => l.includes('DETECTION_MISPREDICTION')), { timeout: 15000 }).toBeTruthy();

  // 6. Verify the player is back in a sane position (not 50, 50)
  const posAfterRollback = await page.evaluate(() => {
    // @ts-ignore
    const p = world.localState.players[world.myPlayerId];
    return { x: p.x, y: p.y };
  });

  console.log(`Position immediately after Rollback: ${posAfterRollback.x}, ${posAfterRollback.y}`);
  expect(posAfterRollback.x).toBeLessThan(20);
  expect(posAfterRollback.y).toBeLessThan(20);

  // 7. STABILITY CHECK: Wait a few more frames and ensure we haven't diverged again
  // (Convergence check)
  await page.waitForTimeout(500);
  const finalPos = await page.evaluate(() => {
    // @ts-ignore
    const p = world.localState.players[world.myPlayerId];
    return { x: p.x, y: p.y };
  });

  console.log(`Final Position after 500ms stability: ${finalPos.x}, ${finalPos.y}`);
  const drift = Math.sqrt(Math.pow(finalPos.x - posAfterRollback.x, 2) + Math.pow(finalPos.y - posAfterRollback.y, 2));
  console.log(`Drift during stability period: ${drift}`);
  
  // Player shouldn't have moved much if we aren't pressing keys now
  expect(drift).toBeLessThan(1.0); 
  expect(finalPos.x).toBeLessThan(20);
});
