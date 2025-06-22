import { TestBed } from '@angular/core/testing';
import {
  HttpClientTestingModule,
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import {
  HTTP_INTERCEPTORS,
  HttpClient,
  HttpErrorResponse,
  HttpRequest,
  HttpEvent,
  provideHttpClient,
  withInterceptors,
  HttpContext,
} from '@angular/common/http';
import { Observable, of, throwError } from 'rxjs';
import { RouterTestingModule } from '@angular/router/testing';
import { Router } from '@angular/router';
import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest'; // Import Vitest globals
import { lastValueFrom } from 'rxjs'; // For async tests


import { AuthInterceptor, authInterceptorFn, BYPASS_AUTH_INTERCEPTOR } from './auth.interceptor';
import { AuthService } from './auth.service';
import { environment } from '@/environments/environment'; // Standardized path alias


// Tests begin here, the duplicated describe and its content above this point are removed.
describe('AuthInterceptor', () => {
  let httpMock: HttpTestingController;
  let httpClient: HttpClient;
  let authService: AuthService;
  let router: Router;

  const mockAccessToken = 'mock-access-token';
  const mockNewAccessToken = 'new-mock-access-token';
  const testUrl = '/api/data';

  // Helper to make a request that will be intercepted
  const makeRequest = (url: string = testUrl, context?: HttpContext): Observable<HttpEvent<any>> => {
    return httpClient.get(url, { context });
  };

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [RouterTestingModule.withRoutes([])],
      providers: [
        AuthService, // Provide real AuthService to spy on its methods
        AuthInterceptor, // Provide the class-based interceptor for DI in authInterceptorFn
        provideHttpClient(withInterceptors([authInterceptorFn])),
        provideHttpClientTesting(), // This provides HttpTestingController
      ],
    });

    httpClient = TestBed.inject(HttpClient);
    httpMock = TestBed.inject(HttpTestingController);
    authService = TestBed.inject(AuthService);
    router = TestBed.inject(Router);

    // Spy on AuthService methods using Vitest
    vi.spyOn(authService, 'getAccessToken');
    vi.spyOn(authService, 'refreshToken');
    vi.spyOn(authService, 'logout').mockImplementation(() => {}); // Mock logout

    localStorage.clear();
  });

  afterEach(() => {
    httpMock.verify();
    localStorage.clear();
    vi.clearAllMocks(); // Clear all Vitest mocks
  });

   it('should add Authorization header if access token exists', () => {
    // Ensure the mock is correctly typed for Vitest if needed, or use generic mockReturnValue
    (authService.getAccessToken as ReturnType<typeof vi.fn>).mockReturnValue(mockAccessToken);

    makeRequest().subscribe();

    const httpRequest = httpMock.expectOne(testUrl);
    expect(httpRequest.request.headers.has('Authorization')).toBe(true);
    expect(httpRequest.request.headers.get('Authorization')).toBe(
      `Bearer ${mockAccessToken}`
    );
    httpRequest.flush({}); // Complete the request
  });

  it('should not add Authorization header if access token does not exist', async () => {
    (authService.getAccessToken as ReturnType<typeof vi.fn>).mockReturnValue(null);

    const reqPromise = lastValueFrom(makeRequest());
    const httpRequest = httpMock.expectOne(testUrl);
    expect(httpRequest.request.headers.has('Authorization')).toBe(false);
    httpRequest.flush({});
    await reqPromise; // ensure subscription completes
  });

  describe('401 Error Handling and Token Refresh', () => {
    it('should attempt to refresh token on 401 error and retry with new token', async () => {
      (authService.getAccessToken as ReturnType<typeof vi.fn>).mockReturnValue(mockAccessToken);
      (authService.refreshToken as ReturnType<typeof vi.fn>).mockReturnValue(of({ accessToken: mockNewAccessToken }));

      const reqPromise = lastValueFrom(makeRequest());

      const failedReq = httpMock.expectOne(testUrl);
      expect(failedReq.request.headers.get('Authorization')).toBe(`Bearer ${mockAccessToken}`);
      failedReq.flush({ message: 'Unauthorized' }, { status: 401, statusText: 'Unauthorized' });

      // refreshToken mock is called by the interceptor
      // No httpMock for refresh call itself as authService.refreshToken is mocked

      const retriedReq = httpMock.expectOne(testUrl);
      expect(retriedReq.request.headers.get('Authorization')).toBe(`Bearer ${mockNewAccessToken}`);
      retriedReq.flush({}); // Simulate successful retry

      await reqPromise; // This will complete if retry is successful
      expect(authService.refreshToken).toHaveBeenCalledTimes(1);
    });

    it('should logout if refresh token call fails', async () => {
      (authService.getAccessToken as ReturnType<typeof vi.fn>).mockReturnValue(mockAccessToken);
      const refreshError = new HttpErrorResponse({ status: 401, error: 'Refresh failed' });
      (authService.refreshToken as ReturnType<typeof vi.fn>).mockReturnValue(throwError(() => refreshError));

      try {
        const reqPromise = lastValueFrom(makeRequest());
        const failedReq = httpMock.expectOne(testUrl);
        failedReq.flush({ message: 'Unauthorized' }, { status: 401, statusText: 'Unauthorized' });
        await reqPromise;
        // Vitest: expect assertion to fail if no error
        expect.fail('Request should have failed');
      } catch (error: any) {
        expect(authService.refreshToken).toHaveBeenCalledTimes(1);
        expect(authService.logout).toHaveBeenCalledTimes(1);
        // The error caught by `lastValueFrom` will be the one from the refreshToken call
        // or the one rethrown by the interceptor after logout.
        expect(error).toBe(refreshError); // Or a new error wrapping it
      }
    });

    it('should not attempt to refresh token for /auth/refresh-token URL on 401 and logout', async () => {
      const refreshTokenUrl = `${environment.apiUrl}/auth/refresh-token`;
      (authService.getAccessToken as ReturnType<typeof vi.fn>).mockReturnValue(mockAccessToken);

      try {
        const reqPromise = lastValueFrom(makeRequest(refreshTokenUrl));
        const req = httpMock.expectOne(refreshTokenUrl);
        req.flush({ message: 'Refresh token invalid' }, { status: 401, statusText: 'Unauthorized' });
        await reqPromise;
        expect.fail('Request should have failed');
      } catch (error: any) {
        expect(error instanceof HttpErrorResponse).toBe(true);
        expect(error.status).toBe(401);
        expect(authService.refreshToken).not.toHaveBeenCalled();
        expect(authService.logout).toHaveBeenCalledTimes(1);
      }
    });

    it('should handle concurrent requests by refreshing token only once', async () => {
      (authService.getAccessToken as ReturnType<typeof vi.fn>).mockReturnValue(mockAccessToken);
      (authService.refreshToken as ReturnType<typeof vi.fn>).mockReturnValue(of({ accessToken: mockNewAccessToken }));

      const req1Promise = lastValueFrom(makeRequest('/api/data1'));
      const req2Promise = lastValueFrom(makeRequest('/api/data2'));

      const failedReq1 = httpMock.expectOne('/api/data1');
      failedReq1.flush({ message: 'Unauthorized' }, { status: 401, statusText: 'Unauthorized' });

      const failedReq2 = httpMock.expectOne('/api/data2');
      failedReq2.flush({ message: 'Unauthorized' }, { status: 401, statusText: 'Unauthorized' });

      // At this point, refreshToken should have been triggered by the first 401.
      // The second 401 should queue behind the ongoing refresh.

      expect(authService.refreshToken).toHaveBeenCalledTimes(1);

      const retriedReq1 = httpMock.expectOne('/api/data1');
      expect(retriedReq1.request.headers.get('Authorization')).toBe(`Bearer ${mockNewAccessToken}`);
      retriedReq1.flush({});

      const retriedReq2 = httpMock.expectOne('/api/data2');
      expect(retriedReq2.request.headers.get('Authorization')).toBe(`Bearer ${mockNewAccessToken}`);
      retriedReq2.flush({});

      await Promise.all([req1Promise, req2Promise]); // Ensure both requests complete successfully
    });

    it('should bypass interceptor if BYPASS_AUTH_INTERCEPTOR context token is true', async () => {
        (authService.getAccessToken as ReturnType<typeof vi.fn>).mockReturnValue(mockAccessToken);
        const context = new HttpContext().set(BYPASS_AUTH_INTERCEPTOR, true);

        const reqPromise = lastValueFrom(makeRequest(testUrl, context));

        const httpRequest = httpMock.expectOne(testUrl);
        // Authorization header should NOT be added by this interceptor's primary logic
        // If other interceptors add it, that's fine, but this one should skip its main processing.
        // For this test, we assume no other interceptors are adding it.
        expect(httpRequest.request.headers.has('Authorization')).toBe(false);
        httpRequest.flush({});
        expect(authService.getAccessToken).not.toHaveBeenCalled(); // getAccessToken is part of the logic to add header
    });

  });
});
