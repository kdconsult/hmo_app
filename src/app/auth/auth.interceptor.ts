import { Injectable, inject } from '@angular/core';
import {
  HttpEvent,
  HttpInterceptorFn,
  HttpHandlerFn,
  HttpRequest,
  HttpErrorResponse,
  HttpContextToken,
  HttpContext,
} from '@angular/common/http';
import { Observable, throwError, BehaviorSubject } from 'rxjs';
import { catchError, filter, switchMap, take } from 'rxjs/operators';
import { AuthService } from './auth.service';
import { Router } from '@angular/router';

// Context token to bypass interception for specific requests (e.g. token refresh itself)
export const BYPASS_AUTH_INTERCEPTOR = new HttpContextToken<boolean>(
  () => false
);

@Injectable()
export class AuthInterceptor {
  private authService = inject(AuthService);
  private router = inject(Router);
  private isRefreshing = false;
  private refreshTokenSubject: BehaviorSubject<any> = new BehaviorSubject<any>(
    null
  );

  intercept(
    req: HttpRequest<any>,
    next: HttpHandlerFn
  ): Observable<HttpEvent<any>> {
    // Allow request to bypass token refresh logic if context is set
    if (req.context.get(BYPASS_AUTH_INTERCEPTOR)) {
      return next(req);
    }

    const accessToken = this.authService.getAccessToken();
    if (accessToken) {
      req = this.addTokenHeader(req, accessToken);
    }

    return next(req).pipe(
      catchError((error) => {
        if (error instanceof HttpErrorResponse && error.status === 401) {
          // Check if the failed request was to the refresh token endpoint itself
          if (req.url.includes('/auth/refresh-token')) {
            // If refresh token fails, logout
            this.authService.logout();
            return throwError(
              () => new Error('Refresh token failed or expired.')
            );
          }
          return this.handle401Error(req, next);
        }
        return throwError(() => error);
      })
    );
  }

  private handle401Error(
    request: HttpRequest<any>,
    next: HttpHandlerFn
  ): Observable<HttpEvent<any>> {
    if (!this.isRefreshing) {
      this.isRefreshing = true;
      this.refreshTokenSubject.next(null);

      return this.authService.refreshToken().pipe(
        switchMap((tokenResponse: any) => {
          this.isRefreshing = false;
          if (tokenResponse && tokenResponse.accessToken) {
            this.refreshTokenSubject.next(tokenResponse.accessToken);
            return next(
              this.addTokenHeader(request, tokenResponse.accessToken)
            );
          } else {
            // Should not happen if refreshToken() handles its errors properly and throws
            this.authService.logout();
            return throwError(
              () =>
                new Error(
                  'Failed to refresh token, no new access token received.'
                )
            );
          }
        }),
        catchError((err) => {
          this.isRefreshing = false;
          this.authService.logout(); // Ensure logout on refresh failure
          return throwError(() => err); // Rethrow the error that caused refresh to fail
        })
      );
    } else {
      // If isRefreshing is true, means a token refresh is already in progress.
      // Wait for refreshTokenSubject to emit a new token (or null if refresh failed)
      return this.refreshTokenSubject.pipe(
        filter((token) => token != null), // Wait until token is not null
        take(1), // Take the first emitted value
        switchMap((jwt) => {
          if (jwt) {
            return next(this.addTokenHeader(request, jwt));
          } else {
            // This case should ideally be handled by the original refresh failing and logging out.
            // If it reaches here, it implies refresh completed but somehow didn't yield a token for subsequent requests.
            this.authService.logout(); // Defensive logout
            return throwError(
              () =>
                new Error(
                  'Token refresh was in progress but resulted in no token.'
                )
            );
          }
        }),
        catchError(() => {
          // This catch is for the refreshTokenSubject pipe if it errors or completes without value
          // which is unlikely if the main refresh logic handles logout.
          this.authService.logout(); // Defensive logout
          return throwError(
            () => new Error('Failed to acquire token after refresh.')
          );
        })
      );
    }
  }

  private addTokenHeader(request: HttpRequest<any>, token: string) {
    return request.clone({
      setHeaders: {
        Authorization: `Bearer ${token}`,
      },
    });
  }
}

// Functional interceptor definition
export const authInterceptorFn: HttpInterceptorFn = (req, next) => {
  return inject(AuthInterceptor).intercept(req, next);
};
