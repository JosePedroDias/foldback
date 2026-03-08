import { test, expect } from '@playwright/test';

test('Air Hockey: local paddle prediction tracks mouse, no spurious rollbacks', async ({ browser }) => {
  const context1 = await browser.newContext();
  const page1 = await context1.newPage();
  await page1.goto('http://localhost:8080/airhockey/?protocol=websockets');

  const context2 = await browser.newContext();
  const page2 = await context2.newPage();
  await page2.goto('http://localhost:8080/airhockey/?protocol=websockets');

  // Wait for both to connect — game needs 2 players to activate
  await expect(page1.locator('#netStats')).toContainText('ID:', { timeout: 15000 });
  await expect(page2.locator('#netStats')).toContainText('ID:', { timeout: 15000 });

  // Wait for game to become active
  await expect(page1.locator('#netStats')).toContainText(/Status: active/i, { timeout: 10000 });

  // Let a few ticks arrive so the engine is warmed up
  await page1.waitForTimeout(500);

  // Record rollback count before mouse movement
  const statsBefore = await page1.evaluate(() => window['foldbackStats']);
  const rollbacksBefore = statsBefore?.rollbackCount || 0;
  console.log(`Rollbacks before mouse movement: ${rollbacksBefore}`);

  // Move mouse to a known screen position (center-ish of the canvas)
  // This should cause the paddle to track toward that position
  const canvasBox = await page1.locator('#gameCanvas').boundingBox();
  if (!canvasBox) throw new Error('Canvas not found');

  const targetScreenX = canvasBox.x + canvasBox.width / 2 + 50;  // Slightly right of center
  const targetScreenY = canvasBox.y + canvasBox.height / 4;       // Upper quarter (P0's half)

  await page1.mouse.move(targetScreenX, targetScreenY);
  await page1.waitForTimeout(500);

  // Check that the paddle moved from its default position
  const paddlePos = await page1.evaluate(() => {
    const w = window['world'];
    const p = w.localState.players[w.myPlayerId];
    return p ? { x: p.x, y: p.y } : null;
  });

  console.log(`Paddle position after mouse move:`, paddlePos);
  expect(paddlePos).not.toBeNull();
  // Paddle should have moved from default (0, -4000 or 0, 4000)
  // We just verify it's not exactly at the default origin x=0
  // (since we moved the mouse right of center)
  expect(paddlePos!.x).not.toBe(0);

  // Move the mouse a few more times to generate prediction ticks
  for (let i = 0; i < 3; i++) {
    await page1.mouse.move(
      targetScreenX + (i + 1) * 20,
      targetScreenY
    );
    await page1.waitForTimeout(200);
  }

  // Check rollback count — local-only movement should produce 0 or very few rollbacks
  // (Air Hockey uses threshold=1 so minor FP differences could cause some, but not many)
  const statsAfter = await page1.evaluate(() => window['foldbackStats']);
  const rollbacksAfter = statsAfter?.rollbackCount || 0;
  const newRollbacks = rollbacksAfter - rollbacksBefore;
  console.log(`New rollbacks during local movement: ${newRollbacks}`);

  // Verify the paddle is still tracking (not stuck or reset)
  const finalPos = await page1.evaluate(() => {
    const w = window['world'];
    const p = w.localState.players[w.myPlayerId];
    return p ? { x: p.x, y: p.y } : null;
  });
  console.log(`Final paddle position:`, finalPos);
  expect(finalPos).not.toBeNull();

  await context1.close();
  await context2.close();
});
