import { TestBed } from '@angular/core/testing';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import {
  HttpClient,
  HttpErrorResponse,
  provideHttpClient,
  withInterceptors,
  HttpContext,
} from '@angular/common/http';
import { of, throwError, Subject } from 'rxjs';
import { Router } from '@angular/router';
import { vi, describe, it, expect, beforeEach, afterEach, Mock } from 'vitest';
import { lastValueFrom } from 'rxjs';
import { provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';

import { authInterceptorFn, BYPASS_AUTH_INTERCEPTOR } from './auth.interceptor';
import { AuthService } from './auth.service';
import { environment } from '@/environments/environment';

describe('authInterceptorFn', () => {
  let httpMock: HttpTestingController;
  let httpClient: HttpClient;
  let authService: AuthService;
  let router: Router;

  const mockAccessToken = 'mock-access-token';
  const mockNewAccessToken = 'new-mock-access-token';
  const testUrl = '/api/data';

  const makeRequest = (
    url: string = testUrl,
    context?: HttpContext
  ): Promise<any> => {
    return lastValueFrom(httpClient.get(url, { context }));
  };

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideZonelessChangeDetection(),
        provideRouter([]), // Mock router providers
        provideHttpClient(withInterceptors([authInterceptorFn])),
        provideHttpClientTesting(),
        {
          provide: AuthService,
          useValue: {
            getAccessToken: vi.fn(),
            refreshToken: vi.fn(),
            logout: vi.fn(),
          },
        },
      ],
    });

    httpClient = TestBed.inject(HttpClient);
    httpMock = TestBed.inject(HttpTestingController);
    authService = TestBed.inject(AuthService);
    router = TestBed.inject(Router);

    vi.spyOn(router, 'navigate').mockResolvedValue(true);
  });

  afterEach(() => {
    httpMock.verify();
    vi.clearAllMocks();
  });

  it('should add Authorization header if access token exists', async () => {
    (authService.getAccessToken as Mock).mockReturnValue(mockAccessToken);

    const requestPromise = makeRequest();

    const httpRequest = httpMock.expectOne(testUrl);
    expect(httpRequest.request.headers.has('Authorization')).toBe(true);
    expect(httpRequest.request.headers.get('Authorization')).toBe(
      `Bearer ${mockAccessToken}`
    );
    httpRequest.flush({});
    await requestPromise;
  });

  it('should not add Authorization header if access token does not exist', async () => {
    (authService.getAccessToken as Mock).mockReturnValue(null);

    const requestPromise = makeRequest();
    const httpRequest = httpMock.expectOne(testUrl);
    expect(httpRequest.request.headers.has('Authorization')).toBe(false);
    httpRequest.flush({});
    await requestPromise;
  });

  describe('401 Error Handling and Token Refresh', () => {
    it('should attempt to refresh token on 401 and retry with new token', async () => {
      (authService.getAccessToken as Mock).mockReturnValue(mockAccessToken);
      (authService.refreshToken as Mock).mockReturnValue(
        of({ accessToken: mockNewAccessToken })
      );

      const requestPromise = makeRequest();

      const failedReq = httpMock.expectOne(testUrl);
      failedReq.flush(
        { message: 'Unauthorized' },
        { status: 401, statusText: 'Unauthorized' }
      );

      const retriedReq = httpMock.expectOne(testUrl);
      expect(retriedReq.request.headers.get('Authorization')).toBe(
        `Bearer ${mockNewAccessToken}`
      );
      retriedReq.flush({});

      await requestPromise;
      expect(authService.refreshToken).toHaveBeenCalledTimes(1);
    });

    it('should logout if refresh token call fails', async () => {
      (authService.getAccessToken as Mock).mockReturnValue(mockAccessToken);
      const refreshError = new HttpErrorResponse({
        status: 401,
        error: 'Refresh failed',
      });
      (authService.refreshToken as Mock).mockReturnValue(
        throwError(() => refreshError)
      );

      const requestPromise = makeRequest();

      const failedReq = httpMock.expectOne(testUrl);
      failedReq.flush(
        { message: 'Unauthorized' },
        { status: 401, statusText: 'Unauthorized' }
      );

      await expect(requestPromise).rejects.toBe(refreshError);

      expect(authService.refreshToken).toHaveBeenCalledTimes(1);
      expect(authService.logout).toHaveBeenCalledTimes(1);
    });

    it('should not attempt refresh token for /auth/refresh-token URL and should logout', async () => {
      const refreshTokenUrl = `${environment.apiUrl}/auth/refresh-token`;
      (authService.getAccessToken as Mock).mockReturnValue(mockAccessToken);

      const requestPromise = makeRequest(refreshTokenUrl);

      const req = httpMock.expectOne(refreshTokenUrl);
      req.flush(
        { message: 'Refresh token invalid' },
        { status: 401, statusText: 'Unauthorized' }
      );

      await expect(requestPromise).rejects.toThrow();
      expect(authService.refreshToken).not.toHaveBeenCalled();
      expect(authService.logout).toHaveBeenCalledTimes(1);
    });

    it('should handle concurrent requests by refreshing token only once', async () => {
      (authService.getAccessToken as Mock).mockReturnValue(mockAccessToken);
      const refreshToken$ = new Subject<{ accessToken: string }>();
      (authService.refreshToken as Mock).mockReturnValue(
        refreshToken$.asObservable()
      );

      const req1Promise = makeRequest('/api/data1');
      const req2Promise = makeRequest('/api/data2');

      const failedReqs = httpMock.match((req) =>
        req.url.startsWith('/api/data')
      );
      expect(failedReqs.length).toBe(2);

      failedReqs[0].flush(
        { message: 'Unauthorized' },
        { status: 401, statusText: 'Unauthorized' }
      );
      failedReqs[1].flush(
        { message: 'Unauthorized' },
        { status: 401, statusText: 'Unauthorized' }
      );

      expect(authService.refreshToken).toHaveBeenCalledTimes(1);

      refreshToken$.next({ accessToken: mockNewAccessToken });
      refreshToken$.complete();

      const retriedReqs = httpMock.match((req) =>
        req.url.startsWith('/api/data')
      );
      expect(retriedReqs.length).toBe(2);

      retriedReqs[0].flush({});
      retriedReqs[1].flush({});

      await Promise.all([req1Promise, req2Promise]);

      expect(retriedReqs[0].request.headers.get('Authorization')).toContain(
        mockNewAccessToken
      );
      expect(retriedReqs[1].request.headers.get('Authorization')).toContain(
        mockNewAccessToken
      );
    });
  });

  it('should bypass interceptor if BYPASS_AUTH_INTERCEPTOR context token is true', async () => {
    const context = new HttpContext().set(BYPASS_AUTH_INTERCEPTOR, true);
    const requestPromise = makeRequest(testUrl, context);

    const httpRequest = httpMock.expectOne(testUrl);
    expect(httpRequest.request.headers.has('Authorization')).toBe(false);

    httpRequest.flush({});
    await requestPromise;
  });
});
