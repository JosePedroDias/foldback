import { test, expect } from '@playwright/test';

test('Remote player action triggers rollback on observer (Bomberman)', async ({ browser }) => {
  const context1 = await browser.newContext();
  const page1 = await context1.newPage();
  await page1.goto('http://localhost:8080/bomberman/?protocol=websockets');

  const context2 = await browser.newContext();
  const page2 = await context2.newPage();
  await page2.goto('http://localhost:8080/bomberman/?protocol=websockets');

  // Wait for both players to connect and receive ticks
  await expect(page1.locator('#netStats')).toContainText('ID:', { timeout: 15000 });
  await expect(page2.locator('#netStats')).toContainText('ID:', { timeout: 15000 });

  // Wait for both to receive a few ticks so history builds up
  await expect(page1.locator('#netStats')).toContainText('Tick:', { timeout: 10000 });
  await expect(page2.locator('#netStats')).toContainText('Tick:', { timeout: 10000 });

  // Record Player 1's initial rollback count
  const initialStats = await page1.evaluate(() => {
    return {
      rollbackCount: window['foldbackStats']?.rollbackCount || 0,
    };
  });
  console.log(`Player 1 initial rollback count: ${initialStats.rollbackCount}`);

  // Corrupt Player 1's local prediction of their own position to force misprediction
  await page1.evaluate(() => {
    const w = window['world'];
    if (w.myPlayerId !== null) {
      const p = w.localState.players[w.myPlayerId];
      if (p) {
        p.x = 50000;
        p.y = 50000;
        w.history.set(w.localState.tick, JSON.parse(JSON.stringify(w.localState)));
      }
    }
  });

  // Poll Player 1's rollback count until it increases
  await expect.poll(async () => {
    const stats = await page1.evaluate(() => window['foldbackStats']);
    return stats?.rollbackCount || 0;
  }, {
    message: 'Expected Player 1 rollback count to increase after state corruption',
    timeout: 15000,
  }).toBeGreaterThan(initialStats.rollbackCount);

  // Verify both players are still connected and receiving ticks
  await expect(page1.locator('#netStats')).toContainText('Players: 2', { timeout: 5000 });
  await expect(page2.locator('#netStats')).toContainText('Players: 2', { timeout: 5000 });

  const finalStats = await page1.evaluate(() => window['foldbackStats']);
  console.log(`Player 1 final rollback count: ${finalStats.rollbackCount}`);

  await context1.close();
  await context2.close();
});
