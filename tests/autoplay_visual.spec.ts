import { chromium, test, expect } from '@playwright/test';

test('Visual Autoplay: Two clients running side-by-side', async () => {
  test.setTimeout(60000);
  // Launching two separate browser instances to control window positions on the OS desktop
  const browser1 = await chromium.launch({ 
    headless: false, 
    args: ['--window-position=0,0', '--window-size=600,800'] 
  });
  const browser2 = await chromium.launch({ 
    headless: false, 
    args: ['--window-position=610,0', '--window-size=600,800'] 
  });

  const page1 = await browser1.newPage();
  const page2 = await browser2.newPage();

  // Auto-accept any dialogs (alerts, confirms, etc.)
  page1.on('dialog', dialog => dialog.accept());
  page2.on('dialog', dialog => dialog.accept());

  console.log("Launching Player 1 with Autoplay...");
  await page1.goto('http://localhost:8080?autoplay=1');
  
  console.log("Launching Player 2 with Autoplay...");
  await page2.goto('http://localhost:8080?autoplay=1');

  // Wait for both to be connected
  await expect(page1.locator('#netStats')).toContainText('Tick:', { timeout: 15000 });
  await expect(page2.locator('#netStats')).toContainText('Tick:', { timeout: 15000 });

  console.log("Both players connected. Running for 20 seconds...");
  
  // Stay active for 20 seconds
  await page1.waitForTimeout(20000);

  const stats1 = await page1.innerText('#netStats');
  const stats2 = await page2.innerText('#netStats');
  
  console.log("Final Stats P1:", stats1);
  console.log("Final Stats P2:", stats2);

  await browser1.close();
  await browser2.close();
});
