import { test, expect } from '@playwright/test';

async function testMultiplayer(browser, game, protocol) {
  const context1 = await browser.newContext();
  const page1 = await context1.newPage();
  await page1.goto(`http://localhost:8080/${game}/?protocol=${protocol}`);

  const context2 = await browser.newContext();
  const page2 = await context2.newPage();
  await page2.goto(`http://localhost:8080/${game}/?protocol=${protocol}`);

  // Both should get an ID
  await expect(page1.locator('#netStats')).toContainText('ID:', { timeout: 20000 });
  await expect(page2.locator('#netStats')).toContainText('ID:', { timeout: 20000 });

  // Both should receive ticks
  await expect(page1.locator('#netStats')).toContainText('Tick:', { timeout: 15000 });
  await expect(page2.locator('#netStats')).toContainText('Tick:', { timeout: 15000 });

  // Both should see at least 2 players (using regex to avoid partial matches like 10)
  await expect(page1.locator('#netStats')).not.toContainText(/Players: [01]$/, { timeout: 15000 });
  await expect(page2.locator('#netStats')).not.toContainText(/Players: [01]$/, { timeout: 15000 });

  // Interaction check
  await page1.keyboard.down('d');
  await page1.waitForTimeout(500);
  await page1.keyboard.up('d');

  // Check if player 2 still sees at least 2 players
  await expect(page2.locator('#netStats')).not.toContainText('Players: 1');

  await context1.close();
  await context2.close();
}

test('Bomberman: Two players can connect via WebSockets', async ({ browser }) => {
  await testMultiplayer(browser, 'bomberman', 'websockets');
});

test('Bomberman: Two players can connect via WebRTC', async ({ browser }) => {
  await testMultiplayer(browser, 'bomberman', 'webrtc');
});
