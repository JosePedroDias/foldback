import { test, expect } from '@playwright/test';

test('Sumo: Linear Interpolation should be active for remote players', async ({ browser }) => {
  const context1 = await browser.newContext();
  const page1 = await context1.newPage();
  await page1.goto('http://localhost:8080/sumo/?protocol=websockets');

  const context2 = await browser.newContext();
  const page2 = await context2.newPage();
  await page2.goto('http://localhost:8080/sumo/?protocol=websockets');

  // Wait for both to connect
  await expect(page1.locator('#netStats')).toContainText('ID:', { timeout: 20000 });
  await expect(page2.locator('#netStats')).toContainText('ID:', { timeout: 20000 });

  const p1Id = await page1.evaluate(() => window['world'].myPlayerId);
  const p2Id = await page2.evaluate(() => window['world'].myPlayerId);

  // Player 1 moves to create delta
  // We use shorter bursts to stay inside the ring
  console.log("Player 1 moving...");
  for (let i = 0; i < 3; i++) {
    await page1.keyboard.down('d');
    await page1.waitForTimeout(100);
    await page1.keyboard.up('d');
    await page1.waitForTimeout(50);
  }

  // Player 2 checks Player 1's state
  // We retry a few times to catch the lag
  let interpCheck;
  for (let i = 0; i < 10; i++) {
    interpCheck = await page2.evaluate((remoteId) => {
      const world = window['world'];
      const rendered = window['renderedState'];
      
      if (!rendered || !rendered.players[remoteId]) return { error: "No rendered remote player" };
      if (!world.authoritativeState.players[remoteId]) return { error: "No authoritative remote player" };

      const authX = world.authoritativeState.players[remoteId].x;
      const rendX = rendered.players[remoteId].x;
      const diff = Math.abs(authX - rendX);

      return { authX, rendX, diff, tick: world.authoritativeState.tick };
    }, p1Id);
    
    console.log(`Try ${i}:`, interpCheck);
    if (interpCheck.diff > 0) break;
    await page2.waitForTimeout(100);
  }

  if (interpCheck['error']) {
    throw new Error(interpCheck['error']);
  }

  // A difference > 0 confirmed that we are NOT just rendering the raw server packet.
  // Given 1 second of movement and 2-tick lag, the difference should be significant.
  expect(interpCheck['diff']).toBeGreaterThan(0);

  await context1.close();
  await context2.close();
});
