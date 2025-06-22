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

import { AuthInterceptor, authInterceptorFn, BYPASS_AUTH_INTERCEPTOR } from './auth.interceptor';
import { AuthService } from './auth.service';
import { environment } from '@/environments/environment';

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
    router = TestBed.inject(Router); // Though not directly used in these interceptor tests, good for setup

    // Spy on AuthService methods
    jest.spyOn(authService, 'getAccessToken');
    jest.spyOn(authService, 'refreshToken');
    jest.spyOn(authService, 'logout').mockImplementation(() => {}); // Mock logout to prevent navigation issues in tests

    // Clear localStorage for clean tests
    localStorage.clear();
  });

  afterEach(() => {
    httpMock.verify();
    localStorage.clear();
  });

  it('should add Authorization header if access token exists', () => {
    (authService.getAccessToken as jest.Mock).mockReturnValue(mockAccessToken);

    makeRequest().subscribe();

    const httpRequest = httpMock.expectOne(testUrl);
    expect(httpRequest.request.headers.has('Authorization')).toBe(true);
    expect(httpRequest.request.headers.get('Authorization')).toBe(
      `Bearer ${mockAccessToken}`
    );
    httpRequest.flush({}); // Complete the request
  });

  it('should not add Authorization header if access token does not exist', () => {
    (authService.getAccessToken as jest.Mock).mockReturnValue(null);

    makeRequest().subscribe();

    const httpRequest = httpMock.expectOne(testUrl);
    expect(httpRequest.request.headers.has('Authorization')).toBe(false);
    httpRequest.flush({});
  });

  describe('401 Error Handling and Token Refresh', () => {
    it('should attempt to refresh token on 401 error', (done) => {
      (authService.getAccessToken as jest.Mock).mockReturnValue(mockAccessToken);
      (authService.refreshToken as jest.Mock).mockReturnValue(of({ accessToken: mockNewAccessToken }));

      makeRequest().subscribe({
        next: () => {
          expect(authService.refreshToken).toHaveBeenCalledTimes(1);
          done();
        },
        error: () => fail('Should have succeeded after token refresh')
      });

      // First request fails with 401
      const failedReq = httpMock.expectOne(testUrl);
      expect(failedReq.request.headers.get('Authorization')).toBe(`Bearer ${mockAccessToken}`);
      failedReq.flush({ message: 'Unauthorized' }, { status: 401, statusText: 'Unauthorized' });

      // Expect refresh token call (interceptor uses authService.refreshToken)
      // authService.refreshToken is mocked, so no httpMock for refresh here unless we test unmocked service

      // Expect original request to be retried with new token
      const retriedReq = httpMock.expectOne(testUrl);
      expect(retriedReq.request.headers.get('Authorization')).toBe(`Bearer ${mockNewAccessToken}`);
      retriedReq.flush({}); // Simulate successful retry
    });

    it('should logout if refresh token call fails', (done) => {
      (authService.getAccessToken as jest.Mock).mockReturnValue(mockAccessToken);
      (authService.refreshToken as jest.Mock).mockReturnValue(throwError(() => new HttpErrorResponse({ status: 401, error: 'Refresh failed' })));

      makeRequest().subscribe({
        next: () => fail('Request should have failed'),
        error: (error) => {
          expect(authService.refreshToken).toHaveBeenCalledTimes(1);
          expect(authService.logout).toHaveBeenCalledTimes(1);
          expect(error.status).toBe(401); // Original 401 error or the refresh error
          done();
        },
      });

      const failedReq = httpMock.expectOne(testUrl);
      failedReq.flush({ message: 'Unauthorized' }, { status: 401, statusText: 'Unauthorized' });
    });


    it('should not attempt to refresh token for /auth/refresh-token URL on 401', (done) => {
        const refreshTokenUrl = `${environment.apiUrl}/auth/refresh-token`;
        (authService.getAccessToken as jest.Mock).mockReturnValue(mockAccessToken); // Token might be present

        makeRequest(refreshTokenUrl).subscribe({
            next: () => fail('Request to refresh token URL itself should not succeed here if it 401s'),
            error: (error: HttpErrorResponse) => {
                expect(error.status).toBe(401);
                expect(authService.refreshToken).not.toHaveBeenCalled(); // Crucial: refresh should not be called
                expect(authService.logout).toHaveBeenCalledTimes(1); // Interceptor should call logout directly
                done();
            }
        });

        const req = httpMock.expectOne(refreshTokenUrl);
        req.flush({ message: 'Refresh token invalid' }, { status: 401, statusText: 'Unauthorized' });
    });


    it('should handle concurrent requests by refreshing token only once', (done) => {
      (authService.getAccessToken as jest.Mock).mockReturnValue(mockAccessToken);
      (authService.refreshToken as jest.Mock).mockReturnValue(of({ accessToken: mockNewAccessToken }).pipe());// Delay pipe removed for simplicity in test

      const request1 = makeRequest('/api/data1');
      const request2 = makeRequest('/api/data2');

      let c1 = false, c2 = false;
      const checkDone = () => { if(c1 && c2) done(); };

      request1.subscribe({ next: () => { c1 = true; checkDone(); }, error: () => fail('req1 failed')});
      request2.subscribe({ next: () => { c2 = true; checkDone(); }, error: () => fail('req2 failed')});

      // Simulate both requests failing with 401
      const failedReq1 = httpMock.expectOne('/api/data1');
      failedReq1.flush({ message: 'Unauthorized' }, { status: 401, statusText: 'Unauthorized' });

      const failedReq2 = httpMock.expectOne('/api/data2');
      failedReq2.flush({ message: 'Unauthorized' }, { status: 401, statusText: 'Unauthorized' });

      // Refresh token should be called only once
      expect(authService.refreshToken).toHaveBeenCalledTimes(1);

      // Both original requests should be retried with the new token
      const retriedReq1 = httpMock.expectOne('/api/data1');
      expect(retriedReq1.request.headers.get('Authorization')).toBe(`Bearer ${mockNewAccessToken}`);
      retriedReq1.flush({});

      const retriedReq2 = httpMock.expectOne('/api/data2');
      expect(retriedReq2.request.headers.get('Authorization')).toBe(`Bearer ${mockNewAccessToken}`);
      retriedReq2.flush({});
    });

    it('should bypass interceptor if BYPASS_AUTH_INTERCEPTOR context token is true', () => {
        (authService.getAccessToken as jest.Mock).mockReturnValue(mockAccessToken);
        const context = new HttpContext().set(BYPASS_AUTH_INTERCEPTOR, true);

        makeRequest(testUrl, context).subscribe();

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
