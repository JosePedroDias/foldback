import { test, expect } from '@playwright/test';

test('Jump and Bump: Single player can connect', async ({ page }) => {
  page.on('console', msg => console.log(`PAGE LOG [${msg.type()}]: ${msg.text()}`));
  page.on('pageerror', error => console.log(`PAGE ERROR: ${error.message}`));

  await page.goto('http://localhost:8080/jumpnbump/?protocol=websockets');

  // It should get an ID
  await expect(page.locator('#netStats')).toContainText('ID:', { timeout: 10000 });
});
