import { test, expect } from '@playwright/test';

async function testPongMultiplayer(browser, protocol) {
  const context1 = await browser.newContext();
  const page1 = await context1.newPage();
  await page1.goto(`http://localhost:8080/pong/?protocol=${protocol}`);

  const context2 = await browser.newContext();
  const page2 = await context2.newPage();
  await page2.goto(`http://localhost:8080/pong/?protocol=${protocol}`);

  // Both should get an ID
  await expect(page1.locator('#netStats')).toContainText('ID:', { timeout: 20000 });
  await expect(page2.locator('#netStats')).toContainText('ID:', { timeout: 20000 });

  // Both should receive ticks
  await expect(page1.locator('#netStats')).toContainText('Tick:', { timeout: 15000 });
  await expect(page2.locator('#netStats')).toContainText('Tick:', { timeout: 15000 });

  // Game should become ACTIVE
  await expect(page1.locator('#netStats')).toContainText('Status: ACTIVE', { timeout: 20000 });
  await expect(page2.locator('#netStats')).toContainText('Status: ACTIVE', { timeout: 20000 });

  await context1.close();
  await context2.close();
}

test('Pong: Two players can connect via WebSockets', async ({ browser }) => {
  await testPongMultiplayer(browser, 'websockets');
});

test('Pong: Two players can connect via WebRTC', async ({ browser }) => {
  await testPongMultiplayer(browser, 'webrtc');
});
