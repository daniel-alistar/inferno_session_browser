const { defineConfig } = require('playwright/test');
module.exports = defineConfig({
  testDir: './test/browser',
  testMatch: '*.spec.cjs',
  workers: 1,
  use: {
    baseURL: 'http://127.0.0.1:4568',
    headless: true,
    channel: process.env.PLAYWRIGHT_BROWSER_CHANNEL || undefined,
    viewport: { width: 1500, height: 1000 },
  },
  webServer: {
    command: `${process.env.BROWSER_TEST_RUBY || 'ruby'} -I lib test/browser/server.rb`,
    url: 'http://127.0.0.1:4568/sessions',
    timeout: 30000,
    reuseExistingServer: !process.env.CI,
  },
});
