import { defineConfig } from 'vitest/config';
import { URL } from 'node:url'; // Import URL for robust path creation

export default defineConfig({
  plugins: [], // No Angular specific plugin for now
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./vitest.setup.ts'], // Will re-create this
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      reportsDirectory: './coverage',
    },
    include: ['src/**/*.spec.ts'],
  },
  resolve: {
    alias: {
      // Consistent with tsconfig.json:
      // "baseUrl": "./src",
      // "paths": {
      //   "@/environments/*": ["./environments/*"],
      //   "@/*": ["./app/*"]
      // }
      // Trusting Angular CLI's Vitest builder to infer paths from tsconfig.json
    },
  },
});
