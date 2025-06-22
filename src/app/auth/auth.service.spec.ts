import { TestBed } from '@angular/core/testing';
import {
  HttpClientTestingModule,
  HttpTestingController,
} from '@angular/common/http/testing';
import { RouterTestingModule } from '@angular/router/testing';
import { Router } from '@angular/router';
import { PLATFORM_ID } from '@angular/core';

import { AuthService } from './auth.service';
import { environment } from '@/environments/environment';
import { jwtDecode, JwtPayload } from 'jwt-decode';

// Mock jwtDecode
jest.mock('jwt-decode', () => ({
  jwtDecode: jest.fn(),
}));

describe('AuthService', () => {
  let service: AuthService;
  let httpMock: HttpTestingController;
  let router: Router;
  let mockJwtDecode = jwtDecode as jest.MockedFunction<typeof jwtDecode>;

  const mockAccessToken = 'mock.access.token';
  const mockRefreshToken = 'mock.refresh.token';
  const mockUserEmail = 'test@example.com';

  const accessTokenKey = environment.tokenKey; //hmo_access_token
  const refreshTokenKey = environment.refreshTokenKey; //hmo_refresh_token


  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [HttpClientTestingModule, RouterTestingModule.withRoutes([])],
      providers: [AuthService, { provide: PLATFORM_ID, useValue: 'browser' }],
    });
    service = TestBed.inject(AuthService);
    httpMock = TestBed.inject(HttpTestingController);
    router = TestBed.inject(Router);
    mockJwtDecode.mockClear(); // Clear mock calls before each test

    // Spy on navigation
    jest.spyOn(router, 'navigate').mockImplementation(() => Promise.resolve(true));


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

  describe('Login', () => {
    it('should store tokens and update isLoggedIn$ on successful login', (done) => {
      const loginCredentials = { email: mockUserEmail, password: 'password' };
      const loginResponse = { accessToken: mockAccessToken, refreshToken: mockRefreshToken };

      // Mock token decoding for isLoggedIn$ update
      const decodedTokenFuture: JwtPayload = { exp: (Date.now() / 1000) + 3600, sub: 'user1' };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);

      service.login(loginCredentials).subscribe(() => {
        expect(localStorage.getItem(accessTokenKey)).toBe(mockAccessToken);
        expect(localStorage.getItem(refreshTokenKey)).toBe(mockRefreshToken);
        service.isLoggedIn$.subscribe(status => {
            if(status) { // wait for true emission
                expect(status).toBe(true);
                done();
            }
        });
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
      expect(req.request.method).toBe('POST');
      req.flush(loginResponse);
    });

    it('should not store tokens and isLoggedIn$ should be false on login failure (no tokens in response)', (done) => {
      const loginCredentials = { email: mockUserEmail, password: 'password' };
      const loginResponse = {}; // Empty response

      service.login(loginCredentials).subscribe({
        next: () => {
          expect(localStorage.getItem(accessTokenKey)).toBeNull();
          expect(localStorage.getItem(refreshTokenKey)).toBeNull();
           service.isLoggedIn$.subscribe(status => {
             expect(status).toBe(false);
             done();
           });
        },
        error: () => fail('Login should not error here, but handle bad response')
      });
      const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
      req.flush(loginResponse); // Simulate backend returning empty or malformed response
    });


    it('should handle HTTP error during login gracefully', (done) => {
        const loginCredentials = { email: mockUserEmail, password: 'password' };
        service.login(loginCredentials).subscribe({
            next: () => fail('Should have failed on HTTP error'),
            error: (err) => {
                expect(err).toBeTruthy();
                expect(localStorage.getItem(accessTokenKey)).toBeNull();
                service.isLoggedIn$.subscribe(status => {
                    expect(status).toBe(false);
                    done();
                });
            }
        });
        const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
        req.flush({ message: 'Invalid credentials' }, { status: 401, statusText: 'Unauthorized' });
    });

  });

  describe('Logout', () => {
    it('should clear tokens, update isLoggedIn$, and navigate to /login', (done) => {
      // Setup: Simulate a logged-in state
      localStorage.setItem(accessTokenKey, mockAccessToken);
      localStorage.setItem(refreshTokenKey, mockRefreshToken);
      const decodedTokenFuture: JwtPayload = { exp: (Date.now() / 1000) + 3600, sub: 'user1' };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);
      service = new AuthService(); // Re-initialize to pick up localStorage in constructor

      service.logout();

      expect(localStorage.getItem(accessTokenKey)).toBeNull();
      expect(localStorage.getItem(refreshTokenKey)).toBeNull();
      expect(router.navigate).toHaveBeenCalledWith(['/login']);
      service.isLoggedIn$.subscribe(status => {
        expect(status).toBe(false);
        done();
      });
    });
  });

  describe('Token Management (isLoggedIn, getUserCompanyId)', () => {
    it('isLoggedIn() should return true for a valid, non-expired token', () => {
      const futureExp = (Date.now() / 1000) + 3600; // 1 hour in future
      mockJwtDecode.mockReturnValue({ exp: futureExp });
      localStorage.setItem(accessTokenKey, mockAccessToken);
      expect(service.isLoggedIn()).toBe(true);
    });

    it('isLoggedIn() should return false for an expired token', () => {
      const pastExp = (Date.now() / 1000) - 3600; // 1 hour in past
      mockJwtDecode.mockReturnValue({ exp: pastExp });
      localStorage.setItem(accessTokenKey, mockAccessToken);
      expect(service.isLoggedIn()).toBe(false);
    });

    it('isLoggedIn() should return false if no token exists', () => {
      localStorage.removeItem(accessTokenKey);
      expect(service.isLoggedIn()).toBe(false);
    });

    it('isLoggedIn() should return false if token is malformed (jwtDecode throws)', () => {
      mockJwtDecode.mockImplementation(() => { throw new Error('Invalid token'); });
      localStorage.setItem(accessTokenKey, 'malformed.token');
      expect(service.isLoggedIn()).toBe(false);
    });

    it('getUserCompanyId() should return company ID from token claims', () => {
      const companyId = 'company-123';
      mockJwtDecode.mockReturnValue({
        exp: (Date.now() / 1000) + 3600,
        'https://hasura.io/jwt/claims': {
          'x-hasura-company-id': companyId,
          'x-hasura-default-role': 'user',
          'x-hasura-allowed-roles': ['user'],
          'x-hasura-user-id': 'user-abc'
        },
      } as any); // Cast to any for simplicity with complex mock type
      localStorage.setItem(accessTokenKey, mockAccessToken);
      expect(service.getUserCompanyId()).toBe(companyId);
    });

    it('getUserCompanyId() should return null if company ID claim is missing', () => {
      mockJwtDecode.mockReturnValue({
        exp: (Date.now() / 1000) + 3600,
        'https://hasura.io/jwt/claims': {
            'x-hasura-default-role': 'user',
            'x-hasura-allowed-roles': ['user'],
            'x-hasura-user-id': 'user-abc'
        },
      }as any);
      localStorage.setItem(accessTokenKey, mockAccessToken);
      expect(service.getUserCompanyId()).toBeNull();
    });

     it('currentCompanyId$ should emit company ID from token', (done) => {
      const companyId = 'company-xyz';
      localStorage.setItem(accessTokenKey, mockAccessToken);
      localStorage.setItem(refreshTokenKey, mockRefreshToken); // Need refresh token for _setTokens
      mockJwtDecode.mockReturnValue({
        exp: (Date.now() / 1000) + 3600,
        'https://hasura.io/jwt/claims': { 'x-hasura-company-id': companyId }
      } as any);

      // Trigger _setTokens which updates currentCompanyId$
      service.updateTokens(mockAccessToken, mockRefreshToken);

      service.currentCompanyId$.subscribe(id => {
        if (id === companyId) { // Wait for specific emission
            expect(id).toBe(companyId);
            done();
        }
      });
    });
  });

  describe('refreshToken', () => {
    it('should successfully refresh token and update stored tokens', (done) => {
      localStorage.setItem(refreshTokenKey, mockRefreshToken);
      const newAccessToken = 'new.access.token';
      const decodedTokenFuture: JwtPayload = { exp: (Date.now() / 1000) + 7200, sub: 'user1' };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);


      service.refreshToken().subscribe(() => {
        expect(localStorage.getItem(accessTokenKey)).toBe(newAccessToken);
        // Assuming refresh token rotation is not implemented or returns the same one
        expect(localStorage.getItem(refreshTokenKey)).toBe(mockRefreshToken);
        service.isLoggedIn$.subscribe(status => {
             if(status) {
                expect(status).toBe(true);
                done();
             }
        });
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/refresh-token`);
      expect(req.request.method).toBe('POST');
      expect(req.request.body).toEqual({ refreshToken: mockRefreshToken });
      expect(req.request.context.get(BYPASS_AUTH_INTERCEPTOR)).toBe(true);
      req.flush({ accessToken: newAccessToken });
    });

    it('should handle refresh token rotation if newRefreshToken is provided', (done) => {
      localStorage.setItem(refreshTokenKey, 'old.refresh.token');
      const newAccessToken = 'new.access.token.rotated';
      const newRefreshTokenRotated = 'new.rotated.refresh.token';
      const decodedTokenFuture: JwtPayload = { exp: (Date.now() / 1000) + 7200, sub: 'user1' };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);

      service.refreshToken().subscribe(() => {
        expect(localStorage.getItem(accessTokenKey)).toBe(newAccessToken);
        expect(localStorage.getItem(refreshTokenKey)).toBe(newRefreshTokenRotated);
        done();
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/refresh-token`);
      req.flush({ accessToken: newAccessToken, newRefreshToken: newRefreshTokenRotated });
    });


    it('should logout if no refresh token is available', (done) => {
      localStorage.removeItem(refreshTokenKey); // Ensure no refresh token

      service.refreshToken().subscribe({
        next: () => fail('Should not succeed without a refresh token'),
        error: (err) => {
          expect(err.message).toContain('No refresh token available');
          expect(router.navigate).toHaveBeenCalledWith(['/login']);
          service.isLoggedIn$.subscribe(status => {
            expect(status).toBe(false);
            done();
          });
        },
      });
    });

    it('should logout if refresh token API call fails', (done) => {
      localStorage.setItem(refreshTokenKey, mockRefreshToken);

      service.refreshToken().subscribe({
        next: () => fail('Should not succeed if API call fails'),
        error: (err) => {
          expect(err).toBeTruthy(); // Check that an error was thrown
          expect(router.navigate).toHaveBeenCalledWith(['/login']);
          service.isLoggedIn$.subscribe(status => {
            expect(status).toBe(false);
            done();
          });
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/refresh-token`);
      req.flush({ message: 'Invalid refresh token' }, { status: 401, statusText: 'Unauthorized' });
    });

     it('should logout if refresh token API call returns no access token', (done) => {
      localStorage.setItem(refreshTokenKey, mockRefreshToken);

      service.refreshToken().subscribe({
        next: () => fail('Should not succeed if API call returns no access token'),
        error: (err) => {
          expect(err.message).toContain('Refresh token endpoint did not return an access token.');
          expect(router.navigate).toHaveBeenCalledWith(['/login']);
          service.isLoggedIn$.subscribe(status => {
            expect(status).toBe(false);
            done();
          });
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/refresh-token`);
      req.flush({}); // Empty response, no access token
    });
  });


  describe('updateTokens', () => {
    it('should update access token and keep existing refresh token if new one is not provided', (done) => {
      const initialRefreshToken = 'initial.refresh.token';
      const newAccessToken = 'updated.access.token';
      localStorage.setItem(refreshTokenKey, initialRefreshToken);
      const decodedTokenFuture: JwtPayload = { exp: (Date.now() / 1000) + 3600, sub: 'user1' };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);


      service.updateTokens(newAccessToken);

      expect(localStorage.getItem(accessTokenKey)).toBe(newAccessToken);
      expect(localStorage.getItem(refreshTokenKey)).toBe(initialRefreshToken); // Should remain the same
      service.isLoggedIn$.subscribe(status => {
        if(status) {
            expect(status).toBe(true); // Check that status reflects new token
            done();
        }
      });
    });

    it('should update both access and refresh tokens if both are provided', () => {
      const newAccessToken = 'updated.access.token.2';
      const newRefreshTokenProvided = 'updated.refresh.token.2';
      const decodedTokenFuture: JwtPayload = { exp: (Date.now() / 1000) + 3600, sub: 'user1' };
      mockJwtDecode.mockReturnValue(decodedTokenFuture);


      service.updateTokens(newAccessToken, newRefreshTokenProvided);

      expect(localStorage.getItem(accessTokenKey)).toBe(newAccessToken);
      expect(localStorage.getItem(refreshTokenKey)).toBe(newRefreshTokenProvided);
    });

    it('should logout if trying to update tokens but no refresh token exists (and none provided)', (done) => {
      localStorage.removeItem(refreshTokenKey); // Ensure no refresh token
      const newAccessToken = 'updated.access.token.3';

      service.updateTokens(newAccessToken); // No refresh token provided

      expect(router.navigate).toHaveBeenCalledWith(['/login']);
      service.isLoggedIn$.subscribe(status => {
        expect(status).toBe(false);
        done();
      });
    });
  });

  // Tests for register, resendVerification, verifyEmailToken, requestPasswordReset, resetPassword
  // These are simpler as they mostly involve direct HTTP calls without complex state changes in AuthService itself
  ['register', 'resendVerification', 'verifyEmailToken', 'requestPasswordReset', 'resetPassword'].forEach(action => {
    describe(action, () => {
      it(`should make a POST request to /auth/${action.toLowerCase().replace('password', '-password')}`, () => {
        const payload = action === 'register' ? { email: 'a', password: 'b' } :
                        action === 'resendVerification' ? { email: 'a' } :
                        action === 'verifyEmailToken' ? { token: 't' } :
                        action === 'requestPasswordReset' ? { email: 'a' } :
                        { token: 't', new_password: 'p' }; // for resetPassword

        const expectedPath = action === 'resetPassword' ? 'reset-password' :
                             action === 'requestPasswordReset' ? 'request-password-reset' :
                             action === 'verifyEmailToken' ? 'verify-email' :
                             action === 'resendVerification' ? 'resend-verification-email' :
                             action;


        (service as any)[action](payload).subscribe(); // Type assertion for dynamic call
        const req = httpMock.expectOne(`${environment.apiUrl}/auth/${expectedPath}`);
        expect(req.request.method).toBe('POST');
        req.flush({});
      });
    });
  });
});
