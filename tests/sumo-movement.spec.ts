import { test, expect } from '@playwright/test';

test('Sumo: Player movement via keyboard', async ({ browser }) => {
  const context = await browser.newContext();
  const page = await context.newPage();
  
  // Connect via WebRTC
  await page.goto('http://localhost:8080/sumo/?protocol=websockets');
  
  // Wait for ID and connection
  await expect(page.locator('#netStats')).toContainText('ID:', { timeout: 15000 });
  
  // Get initial state
  const initialY = await page.evaluate(() => {
    const pid = window.world.myPlayerId;
    return window.world.localState.players[pid].y;
  });
  
  console.log(`Initial Y: ${initialY}`);

  // Press 'w' for some time (Sumo 'w' is dy = -1)
  await page.keyboard.down('w');
  await page.waitForTimeout(1000); // 1 second of movement
  await page.keyboard.up('w');
  
  // Wait a few more ticks for prediction/server update
  await page.waitForTimeout(1000);

  // Get new state
  const finalY = await page.evaluate(() => {
    const pid = window.world.myPlayerId;
    return window.world.localState.players[pid].y;
  });
  
  console.log(`Final Y: ${finalY}`);

  // In Sumo, 'w' is dy = -1, so Y should decrease
  expect(finalY).toBeLessThan(initialY);
  
  await context.close();
});
