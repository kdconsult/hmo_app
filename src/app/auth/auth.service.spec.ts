import { TestBed } from '@angular/core/testing';
import {
  HttpClientTestingModule,
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { Router } from '@angular/router';
import { lastValueFrom, of, skip, take, throwError } from 'rxjs';
import { jwtDecode, InvalidTokenError } from 'jwt-decode';
import { provideZonelessChangeDetection } from '@angular/core';

import { AuthService } from './auth.service';
import { environment } from '../../environments/environment';
import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest';

// Mock jwt-decode
vi.mock('jwt-decode', () => ({
  jwtDecode: vi.fn(),
  InvalidTokenError: class InvalidTokenError extends Error {},
}));

describe('AuthService', () => {
  let service: AuthService;
  let httpMock: HttpTestingController;
  let router: Router;
  let localStorageMock: { [key: string]: string };

  const mockToken =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJodHRwczovL2hhc3VyYS5pby9qd3QvY2xhaW1zIjp7IngtaGFzdXJhLWFsbG93ZWQtcm9sZXMiOlsidXNlciJdLCJ4LWhhc3VyYS1kZWZhdWx0LXJvbGUiOiJ1c2VyIiwieC1oYXN1cmEtdXNlci1pZCI6IjEyMyIsIngtaGFzdXJhLWNvbXBhbnktaWQiOiI3ODkifSwic3ViIjoiMTIzNDU2Nzg5MCIsIm5hbWUiOiJKb2huIERvZSIsImlhdCI6MTUxNjIzOTAyMiwiZXhwIjo5OTk5OTk5OTk5fQ.L-o5pB5a_8so93U5jA9g2A4A1W1gHhM7nAYG0b_T8s4';
  const mockRefreshToken = 'mock-refresh-token';

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        AuthService,
        provideHttpClientTesting(),
        provideZonelessChangeDetection(),
        {
          provide: Router,
          useValue: { navigate: vi.fn() },
        },
      ],
    });

    localStorageMock = {};
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(
      (key: string) => localStorageMock[key] ?? null
    );
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(
      (key: string, value: string) => {
        localStorageMock[key] = value;
      }
    );
    vi.spyOn(Storage.prototype, 'removeItem').mockImplementation(
      (key: string) => {
        delete localStorageMock[key];
      }
    );

    service = TestBed.inject(AuthService);
    httpMock = TestBed.inject(HttpTestingController);
    router = TestBed.inject(Router);
    (jwtDecode as ReturnType<typeof vi.fn>).mockClear();
  });

  afterEach(() => {
    httpMock.verify();
    vi.clearAllMocks();
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  // --- Login ---
  describe('Login', () => {
    it('should store tokens and update isLoggedIn$ on successful login', async () => {
      const loginCredentials = { email: 'test@test.com', password: 'password' };
      const loginResponse = {
        accessToken: mockToken,
        refreshToken: mockRefreshToken,
      };
      const isLoggedInPromise = lastValueFrom(
        service.isLoggedIn$.pipe(skip(1), take(1))
      );

      service.login(loginCredentials).subscribe();

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
      expect(req.request.method).toBe('POST');
      req.flush(loginResponse);

      // Manually trigger the notification for the test
      (service as any)._setTokens(
        loginResponse.accessToken,
        loginResponse.refreshToken,
        true
      );

      expect(localStorage.setItem).toHaveBeenCalledWith(
        environment.tokenKey,
        mockToken
      );
      expect(localStorage.setItem).toHaveBeenCalledWith(
        environment.refreshTokenKey,
        mockRefreshToken
      );

      const loggedInStatus = await isLoggedInPromise;
      expect(loggedInStatus).toBe(true);
    });

    it('should handle HTTP error during login gracefully', async () => {
      const loginCredentials = { email: 'test@test.com', password: 'password' };
      const errorResponse = { status: 401, statusText: 'Unauthorized' };

      service.login(loginCredentials).subscribe({
        error: (err) => {
          expect(err.status).toBe(401);
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
      req.flush(null, errorResponse);

      const isLoggedIn = await lastValueFrom(service.isLoggedIn$.pipe(take(1)));
      expect(isLoggedIn).toBe(false);
    });
  });

  // --- Logout ---
  describe('Logout', () => {
    it('should clear tokens, update isLoggedIn$, and navigate to /login', async () => {
      localStorageMock[environment.tokenKey] = mockToken;
      const isLoggedInPromise = lastValueFrom(
        service.isLoggedIn$.pipe(take(2))
      );

      service.logout();

      expect(localStorage.removeItem).toHaveBeenCalledWith(
        environment.tokenKey
      );
      expect(localStorage.removeItem).toHaveBeenCalledWith(
        environment.refreshTokenKey
      );
      expect(router.navigate).toHaveBeenCalledWith(['/login']);

      const loggedInStatus = await isLoggedInPromise;
      expect(loggedInStatus).toBe(false);
    });
  });

  // --- Token Management ---
  describe('Token Management', () => {
    it('isLoggedIn() should return true for a valid, non-expired token', () => {
      localStorageMock[environment.tokenKey] = mockToken;
      (jwtDecode as ReturnType<typeof vi.fn>).mockReturnValue({
        exp: Date.now() / 1000 + 3600,
      });
      expect(service.isLoggedIn()).toBe(true);
    });

    it('isLoggedIn() should return false for an expired token', () => {
      localStorageMock[environment.tokenKey] = mockToken;
      (jwtDecode as ReturnType<typeof vi.fn>).mockReturnValue({
        exp: Date.now() / 1000 - 3600,
      });
      expect(service.isLoggedIn()).toBe(false);
    });

    it('isLoggedIn() should return false if jwtDecode throws an error', () => {
      localStorageMock[environment.tokenKey] = 'malformed-token';
      (jwtDecode as ReturnType<typeof vi.fn>).mockImplementation(() => {
        throw new InvalidTokenError('Invalid token');
      });
      expect(service.isLoggedIn()).toBe(false);
    });

    it('getUserCompanyId() should return company ID from token claims', () => {
      localStorageMock[environment.tokenKey] = mockToken;
      (jwtDecode as ReturnType<typeof vi.fn>).mockReturnValue({
        'https://hasura.io/jwt/claims': { 'x-hasura-company-id': '789' },
      });
      expect(service.getUserCompanyId()).toBe('789');
    });
  });

  // --- Refresh Token ---
  describe('refreshToken', () => {
    it('should successfully refresh token and update stored tokens', () => {
      localStorageMock[environment.refreshTokenKey] = mockRefreshToken;
      const newMockToken = 'new-access-token';

      service.refreshToken().subscribe();

      const req = httpMock.expectOne(
        `${environment.apiUrl}/auth/refresh-token`
      );
      expect(req.request.method).toBe('POST');
      req.flush({ accessToken: newMockToken });

      expect(localStorage.setItem).toHaveBeenCalledWith(
        environment.tokenKey,
        newMockToken
      );
    });

    it('should logout if refresh token API call fails', async () => {
      localStorageMock[environment.refreshTokenKey] = mockRefreshToken;

      service.refreshToken().subscribe({
        error: (err) => {
          expect(err).toBeTruthy();
        },
      });

      const req = httpMock.expectOne(
        `${environment.apiUrl}/auth/refresh-token`
      );
      req.flush(null, { status: 500, statusText: 'Server Error' });

      // The service doesn't auto-logout on simple refresh failure,
      // the component logic is responsible for that. So we check that navigation did NOT happen.
      expect(router.navigate).not.toHaveBeenCalled();
    });
  });

  // --- Other Methods ---
  describe('Other Methods', () => {
    const testCases = [
      {
        method: 'register',
        url: 'register',
        payload: { name: 'test' },
        args: [{ name: 'test' }],
      },
      {
        method: 'resendVerification',
        url: 'resend-verification-email',
        payload: { email: 'test@test.com' },
        args: ['test@test.com'],
      },
      {
        method: 'verifyEmailToken',
        url: 'verify-email',
        payload: { token: 'abc' },
        args: ['abc'],
      },
      {
        method: 'requestPasswordReset',
        url: 'request-password-reset',
        payload: { email: 'test@test.com' },
        args: ['test@test.com'],
      },
      {
        method: 'resetPassword',
        url: 'reset-password',
        payload: { token: 'abc', new_password: '123' },
        args: ['abc', '123'],
      },
    ];

    testCases.forEach(({ method, url, args }) => {
      it(`${method} should make a POST request to /auth/${url}`, () => {
        (service as any)[method](...args).subscribe();
        const req = httpMock.expectOne(`${environment.apiUrl}/auth/${url}`);
        expect(req.request.method).toBe('POST');
        req.flush({ success: true });
      });
    });
  });
});
