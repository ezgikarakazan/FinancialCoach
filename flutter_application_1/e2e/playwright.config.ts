import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  reporter: 'list',
  use: {
    baseURL: process.env.API_BASE_URL ?? 'http://127.0.0.1:8000',
  },
});
