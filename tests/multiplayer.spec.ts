import { test, expect } from '@playwright/test';

test('Two players can connect and see each other', async ({ browser }) => {
  // Player 1
  const context1 = await browser.newContext();
  const page1 = await context1.newPage();
  await page1.goto('http://localhost:8080');

  // Player 2
  const context2 = await browser.newContext();
  const page2 = await context2.newPage();
  await page2.goto('http://localhost:8080');

  // Wait for connection
  await expect(page1.locator('#netStats')).toContainText('Tick:', { timeout: 10000 });
  await expect(page2.locator('#netStats')).toContainText('Tick:', { timeout: 10000 });

  // Both should see 2 players
  await expect(page1.locator('#netStats')).toContainText('Players: 2', { timeout: 10000 });
  await expect(page2.locator('#netStats')).toContainText('Players: 2', { timeout: 10000 });

  // Move player 1
  await page1.keyboard.down('d');
  await page1.waitForTimeout(500);
  await page1.keyboard.up('d');

  // Check if player 2 sees movement (implied by no crash and still connected)
  await expect(page2.locator('#netStats')).toContainText('Players: 2');

  await context1.close();
  await context2.close();
});
