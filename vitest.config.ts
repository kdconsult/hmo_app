import { defineConfig } from 'vitest/config';
import path from 'node:path';

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
    alias: [
      {
        find: '@',
        replacement: path.resolve(__dirname, 'src'),
      },
    ],
  },
});
