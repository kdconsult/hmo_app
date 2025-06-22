import 'zone.js';
import 'zone.js/testing';
import { getTestBed } from '@angular/core/testing';
import {
  BrowserDynamicTestingModule,
  platformBrowserDynamicTesting,
} from '@angular/platform-browser-dynamic/testing';
import { vi } from 'vitest';

// Initialize Angular testing environment
getTestBed().initTestEnvironment(
  BrowserDynamicTestingModule,
  platformBrowserDynamicTesting()
);

// Mock IntersectionObserver (useful for components using it)
const mockIntersectionObserver = vi.fn();
mockIntersectionObserver.mockReturnValue({
  observe: vi.fn(),
  unobserve: vi.fn(),
  disconnect: vi.fn(),
});
Object.defineProperty(window, 'IntersectionObserver', {
    value: mockIntersectionObserver,
    writable: true,
});

// Add any other global mocks or setup needed for all tests here.
// For example, mocking localStorage if not handled per-suite:
// const mockLocalStorage = (() => {
//   let store: { [key: string]: string } = {};
//   return {
//     getItem: (key: string) => store[key] || null,
//     setItem: (key: string, value: string) => { store[key] = value.toString(); },
//     removeItem: (key: string) => { delete store[key]; },
//     clear: () => { store = {}; },
//     key: (index: number) => Object.keys(store)[index] || null,
//     get length() { return Object.keys(store).length; }
//   };
// })();
// Object.defineProperty(window, 'localStorage', { value: mockLocalStorage });
// However, it's often better to manage localStorage mocks within specific test suites (e.g. auth.service.spec.ts)
// to avoid polluting the global scope and ensure test isolation.
// The auth.service.spec.ts already handles its localStorage interactions and clearing.
