import { TestBed } from '@angular/core/testing';
import { HttpTestingController } from '@angular/common/http/testing';
import { RouterTestingModule } from '@angular/router/testing';
import { Router } from '@angular/router';
import { PLATFORM_ID } from '@angular/core';
import { filter, take } from 'rxjs/operators'; // Import filter and take

import { AuthService } from './auth.service';
import { environment } from '@/environments/environment';
import { jwtDecode, JwtPayload } from 'jwt-decode';
import { firstValueFrom, lastValueFrom, Observable } from 'rxjs';

import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest'; // Import Vitest globals
import { HttpContextToken } from '@angular/common/http';

// Mock jwt-decode using Vitest's mocking
vi.mock('jwt-decode', () => ({
  jwtDecode: vi.fn(),
}));

describe('AuthService', () => {
  let service: AuthService;
  let httpMock: HttpTestingController;
  let router: Router;
  // Cast to Vitest's MockedFunction type
  let mockJwtDecode = jwtDecode as ReturnType<typeof vi.fn>;

  const mockAccessToken = 'mock.access.token';
  const mockRefreshToken = 'mock.refresh.token';
  const mockUserEmail = 'test@example.com';

  const accessTokenKey = environment.tokenKey; //hmo_access_token
  const refreshTokenKey = environment.refreshTokenKey; //hmo_refresh_token

  const BYPASS_AUTH_INTERCEPTOR = new HttpContextToken<boolean>(() => false);

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [RouterTestingModule.withRoutes([])],
      providers: [AuthService, { provide: PLATFORM_ID, useValue: 'browser' }],
    });
    service = TestBed.inject(AuthService);
    httpMock = TestBed.inject(HttpTestingController);
    router = TestBed.inject(Router);
    mockJwtDecode.mockClear(); // This is fine for vi.fn() as well

    // Spy on navigation using Vitest
    vi.spyOn(router, 'navigate').mockImplementation(() =>
      Promise.resolve(true)
    );

    // Clear localStorage before each test for a clean slate
    localStorage.clear();
  });

  afterEach(() => {
    httpMock.verify(); // Ensure no outstanding HTTP requests
    localStorage.clear(); // Clean up localStorage after each test
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  // NOTE: The duplicated describe('AuthService', ...) block that started here has been removed.

  describe('Login', () => {
    it('should store tokens and update isLoggedIn$ on successful login', async () => {
      const loginCredentials = { email: mockUserEmail, password: 'password' };
      const loginResponse = {
        accessToken: mockAccessToken,
        refreshToken: mockRefreshToken,
      };
      const decodedTokenFuture: JwtPayload = {
        exp: Date.now() / 1000 + 3600,
        sub: 'user1',
      };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);

      // Use a promise to wait for isLoggedIn$ to emit true
      const loggedInPromise = firstValueFrom(
        service.isLoggedIn$.pipe(
          filter((status) => status === true),
          take(1)
        )
      );

      const loginObservable = service.login(loginCredentials);
      const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
      expect(req.request.method).toBe('POST');
      req.flush(loginResponse);

      await lastValueFrom(loginObservable); // Wait for login to complete

      expect(localStorage.getItem(accessTokenKey)).toBe(mockAccessToken);
      expect(localStorage.getItem(refreshTokenKey)).toBe(mockRefreshToken);

      const status = await loggedInPromise;
      expect(status).toBe(true);
    });

    it('should not store tokens and isLoggedIn$ should be false on login failure (no tokens in response)', async () => {
      const loginCredentials = { email: mockUserEmail, password: 'password' };
      const loginResponse = {}; // Empty response

      // isLoggedIn$ should already be false or become false
      const isLoggedInFalsePromise = firstValueFrom(
        service.isLoggedIn$.pipe(
          filter((s) => !s),
          take(1)
        )
      );

      const loginObservable = service.login(loginCredentials);
      const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
      req.flush(loginResponse);

      await lastValueFrom(loginObservable);

      expect(localStorage.getItem(accessTokenKey)).toBeNull();
      expect(localStorage.getItem(refreshTokenKey)).toBeNull();

      const status = await isLoggedInFalsePromise;
      expect(status).toBe(false);
    });

    it('should handle HTTP error during login gracefully', async () => {
      const loginCredentials = { email: mockUserEmail, password: 'password' };
      const isLoggedInFalsePromise = firstValueFrom(
        service.isLoggedIn$.pipe(
          filter((s) => !s),
          take(1)
        )
      );

      try {
        const loginObservable = service.login(loginCredentials);
        const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
        req.flush(
          { message: 'Invalid credentials' },
          { status: 401, statusText: 'Unauthorized' }
        );
        await lastValueFrom(loginObservable);
        // Should not reach here if error is thrown by service's observable chain
      } catch (err: any) {
        expect(err).toBeTruthy();
        expect(err.status).toBe(401); // Check the error object
      }

      expect(localStorage.getItem(accessTokenKey)).toBeNull();
      const status = await isLoggedInFalsePromise;
      expect(status).toBe(false);
    });
  });

  describe('Logout', () => {
    it('should clear tokens, update isLoggedIn$, and navigate to /login', async () => {
      // Setup: Simulate a logged-in state
      localStorage.setItem(accessTokenKey, mockAccessToken);
      localStorage.setItem(refreshTokenKey, mockRefreshToken);
      const decodedTokenFuture: JwtPayload = {
        exp: Date.now() / 1000 + 3600,
        sub: 'user1',
      };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);
      service = TestBed.inject(AuthService); // Re-initialize to pick up localStorage in constructor for loggedInStatus
      const isLoggedInFalsePromise = firstValueFrom(
        service.isLoggedIn$.pipe(
          filter((s) => !s),
          take(1)
        )
      );

      service.logout();

      expect(localStorage.getItem(accessTokenKey)).toBeNull();
      expect(localStorage.getItem(refreshTokenKey)).toBeNull();
      expect(router.navigate).toHaveBeenCalledWith(['/login']);

      const status = await isLoggedInFalsePromise;
      expect(status).toBe(false);
    });
  });

  describe('Token Management (isLoggedIn, getUserCompanyId)', () => {
    it('isLoggedIn() should return true for a valid, non-expired token', () => {
      const futureExp = Date.now() / 1000 + 3600;
      mockJwtDecode.mockReturnValue({ exp: futureExp } as JwtPayload);
      localStorage.setItem(accessTokenKey, mockAccessToken);
      service = TestBed.inject(AuthService); // Re-init to pick up new localStorage state for constructor
      expect(service.isLoggedIn()).toBe(true);
    });

    it('isLoggedIn() should return false for an expired token', () => {
      const pastExp = Date.now() / 1000 - 3600;
      mockJwtDecode.mockReturnValue({ exp: pastExp } as JwtPayload);
      localStorage.setItem(accessTokenKey, mockAccessToken);
      service = TestBed.inject(AuthService);
      expect(service.isLoggedIn()).toBe(false);
    });

    it('isLoggedIn() should return false if no token exists', () => {
      localStorage.removeItem(accessTokenKey);
      service = TestBed.inject(AuthService);
      expect(service.isLoggedIn()).toBe(false);
    });

    it('isLoggedIn() should return false if token is malformed (jwtDecode throws)', () => {
      mockJwtDecode.mockImplementation(() => {
        throw new Error('Invalid token');
      });
      localStorage.setItem(accessTokenKey, 'malformed.token');
      service = TestBed.inject(AuthService);
      expect(service.isLoggedIn()).toBe(false);
    });

    it('getUserCompanyId() should return company ID from token claims', () => {
      const companyId = 'company-123';
      mockJwtDecode.mockReturnValue({
        exp: Date.now() / 1000 + 3600,
        'https://hasura.io/jwt/claims': {
          'x-hasura-company-id': companyId,
          'x-hasura-default-role': 'user',
          'x-hasura-allowed-roles': ['user'],
          'x-hasura-user-id': 'user-abc',
        },
      } as any);
      localStorage.setItem(accessTokenKey, mockAccessToken);
      service = TestBed.inject(AuthService);
      expect(service.getUserCompanyId()).toBe(companyId);
    });

    it('getUserCompanyId() should return null if company ID claim is missing', () => {
      mockJwtDecode.mockReturnValue({
        exp: Date.now() / 1000 + 3600,
        'https://hasura.io/jwt/claims': {
          'x-hasura-default-role': 'user',
          'x-hasura-allowed-roles': ['user'],
          'x-hasura-user-id': 'user-abc',
        },
      } as any);
      localStorage.setItem(accessTokenKey, mockAccessToken);
      service = TestBed.inject(AuthService);
      expect(service.getUserCompanyId()).toBeNull();
    });

    it('currentCompanyId$ should emit company ID from token', async () => {
      const companyId = 'company-xyz';
      localStorage.setItem(accessTokenKey, mockAccessToken);
      localStorage.setItem(refreshTokenKey, mockRefreshToken);
      mockJwtDecode.mockReturnValue({
        exp: Date.now() / 1000 + 3600,
        'https://hasura.io/jwt/claims': { 'x-hasura-company-id': companyId },
      } as any);

      // Need to re-initialize service or call a method that updates the BehaviorSubject
      // Here, calling updateTokens will internally call _setTokens which updates currentCompanyId$
      service.updateTokens(mockAccessToken, mockRefreshToken);

      const id = await firstValueFrom(
        service.currentCompanyId$.pipe(
          filter((val) => val === companyId),
          take(1)
        )
      );
      expect(id).toBe(companyId);
    });
  });

  describe('refreshToken', () => {
    it('should successfully refresh token and update stored tokens', async () => {
      localStorage.setItem(refreshTokenKey, mockRefreshToken);
      const newAccessToken = 'new.access.token';
      const decodedTokenFuture: JwtPayload = {
        exp: Date.now() / 1000 + 7200,
        sub: 'user1',
      };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);

      const loggedInPromise = firstValueFrom(
        service.isLoggedIn$.pipe(
          filter((status) => status === true),
          take(1)
        )
      );

      const refreshObservable = service.refreshToken();
      const req = httpMock.expectOne(
        `${environment.apiUrl}/auth/refresh-token`
      );
      expect(req.request.method).toBe('POST');
      expect(req.request.body).toEqual({ refreshToken: mockRefreshToken });
      expect(req.request.context.get(BYPASS_AUTH_INTERCEPTOR)).toBe(true);
      req.flush({ accessToken: newAccessToken });

      await lastValueFrom(refreshObservable);

      expect(localStorage.getItem(accessTokenKey)).toBe(newAccessToken);
      expect(localStorage.getItem(refreshTokenKey)).toBe(mockRefreshToken); // Assuming no rotation in this response
      const status = await loggedInPromise;
      expect(status).toBe(true);
    });

    it('should handle refresh token rotation if newRefreshToken is provided', async () => {
      localStorage.setItem(refreshTokenKey, 'old.refresh.token');
      const newAccessToken = 'new.access.token.rotated';
      const newRefreshTokenRotated = 'new.rotated.refresh.token';
      mockJwtDecode.mockReturnValue({
        exp: Date.now() / 1000 + 7200,
      } as JwtPayload);

      const refreshObservable = service.refreshToken();
      const req = httpMock.expectOne(
        `${environment.apiUrl}/auth/refresh-token`
      );
      req.flush({
        accessToken: newAccessToken,
        newRefreshToken: newRefreshTokenRotated,
      });

      await lastValueFrom(refreshObservable);

      expect(localStorage.getItem(accessTokenKey)).toBe(newAccessToken);
      expect(localStorage.getItem(refreshTokenKey)).toBe(
        newRefreshTokenRotated
      );
    });

    it('should logout if no refresh token is available', async () => {
      localStorage.removeItem(refreshTokenKey);
      const isLoggedInFalsePromise = firstValueFrom(
        service.isLoggedIn$.pipe(
          filter((s) => !s),
          take(1)
        )
      );

      try {
        await lastValueFrom(service.refreshToken());
        // Vitest's expect.toThrow might be better here if the observable directly throws
      } catch (err: any) {
        expect(err.message).toContain('No refresh token available');
      }
      expect(router.navigate).toHaveBeenCalledWith(['/login']);
      const status = await isLoggedInFalsePromise;
      expect(status).toBe(false);
    });

    it('should logout if refresh token API call fails', async () => {
      localStorage.setItem(refreshTokenKey, mockRefreshToken);
      const isLoggedInFalsePromise = firstValueFrom(
        service.isLoggedIn$.pipe(
          filter((s) => !s),
          take(1)
        )
      );

      try {
        const refreshObservable = service.refreshToken();
        const req = httpMock.expectOne(
          `${environment.apiUrl}/auth/refresh-token`
        );
        req.flush(
          { message: 'Invalid refresh token' },
          { status: 401, statusText: 'Unauthorized' }
        );
        await lastValueFrom(refreshObservable);
      } catch (err: any) {
        expect(err).toBeTruthy();
      }
      expect(router.navigate).toHaveBeenCalledWith(['/login']);
      const status = await isLoggedInFalsePromise;
      expect(status).toBe(false);
    });

    it('should logout if refresh token API call returns no access token', async () => {
      localStorage.setItem(refreshTokenKey, mockRefreshToken);
      const isLoggedInFalsePromise = firstValueFrom(
        service.isLoggedIn$.pipe(
          filter((s) => !s),
          take(1)
        )
      );

      try {
        const refreshObservable = service.refreshToken();
        const req = httpMock.expectOne(
          `${environment.apiUrl}/auth/refresh-token`
        );
        req.flush({}); // Empty response
        await lastValueFrom(refreshObservable);
      } catch (err: any) {
        expect(err.message).toContain(
          'Refresh token endpoint did not return an access token.'
        );
      }
      expect(router.navigate).toHaveBeenCalledWith(['/login']);
      const status = await isLoggedInFalsePromise;
      expect(status).toBe(false);
    });
  });

  describe('updateTokens', () => {
    it('should update access token and keep existing refresh token if new one is not provided', async () => {
      const initialRefreshToken = 'initial.refresh.token';
      const newAccessToken = 'updated.access.token';
      localStorage.setItem(refreshTokenKey, initialRefreshToken); // Ensure initial refresh token is set
      const decodedTokenFuture: JwtPayload = {
        exp: Date.now() / 1000 + 3600,
        sub: 'user1',
      };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);

      const isLoggedInTruePromise = firstValueFrom(
        service.isLoggedIn$.pipe(
          filter((status) => status === true),
          take(1)
        )
      );

      service.updateTokens(newAccessToken);

      expect(localStorage.getItem(accessTokenKey)).toBe(newAccessToken);
      expect(localStorage.getItem(refreshTokenKey)).toBe(initialRefreshToken); // Should remain the same

      const status = await isLoggedInTruePromise;
      expect(status).toBe(true); // Check that status reflects new token
    });

    it('should update both access and refresh tokens if both are provided', async () => {
      const newAccessToken = 'updated.access.token.2';
      const newRefreshTokenProvided = 'updated.refresh.token.2';
      const decodedTokenFuture: JwtPayload = {
        exp: Date.now() / 1000 + 3600,
        sub: 'user1',
      };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);

      service.updateTokens(newAccessToken, newRefreshTokenProvided);

      expect(localStorage.getItem(accessTokenKey)).toBe(newAccessToken);
      expect(localStorage.getItem(refreshTokenKey)).toBe(
        newRefreshTokenProvided
      );
      // Check isLoggedIn$ or currentCompanyId$ if they are expected to change and be stable after this
      // For now, just checking localStorage is sufficient for this specific test's scope.
    });

    it('should logout if trying to update tokens but no refresh token exists (and none provided)', async () => {
      localStorage.removeItem(refreshTokenKey); // Ensure no refresh token
      const newAccessToken = 'updated.access.token.3';
      const isLoggedInFalsePromise = firstValueFrom(
        service.isLoggedIn$.pipe(
          filter((s) => !s),
          take(1)
        )
      );

      service.updateTokens(newAccessToken); // No refresh token provided

      expect(router.navigate).toHaveBeenCalledWith(['/login']);
      const status = await isLoggedInFalsePromise;
      expect(status).toBe(false);
    });
  });

  // Tests for register, resendVerification, verifyEmailToken, requestPasswordReset, resetPassword
  // These are simpler as they mostly involve direct HTTP calls without complex state changes in AuthService itself
  const simpleAuthActions = [
    {
      name: 'register',
      payload: { email: 'a', password: 'b' },
      path: 'register',
    },
    {
      name: 'resendVerification',
      payload: { email: 'a' },
      path: 'resend-verification-email',
    },
    { name: 'verifyEmailToken', payload: { token: 't' }, path: 'verify-email' },
    {
      name: 'requestPasswordReset',
      payload: { email: 'a' },
      path: 'request-password-reset',
    },
    {
      name: 'resetPassword',
      payload: { token: 't', new_password: 'p' },
      path: 'reset-password',
    },
  ];

  simpleAuthActions.forEach((actionInfo) => {
    describe(actionInfo.name, () => {
      it(`should make a POST request to /auth/${actionInfo.path}`, async () => {
        // Type assertion to call method by string name
        const methodToCall = (service as any)[actionInfo.name] as (
          payload: any
        ) => Observable<any>;

        const requestObservable = methodToCall(actionInfo.payload);
        const reqPromise = new Promise<void>((resolve) => {
          const s = requestObservable.subscribe({
            complete: () => {
              s.unsubscribe();
              resolve();
            },
            error: () => {
              s.unsubscribe();
              resolve();
            },
          });
        });

        const req = httpMock.expectOne(
          `${environment.apiUrl}/auth/${actionInfo.path}`
        );
        expect(req.request.method).toBe('POST');
        req.flush({}); // Respond with empty object for success

        await reqPromise; // Ensure the request handling completes
      });
    });
  });
});
