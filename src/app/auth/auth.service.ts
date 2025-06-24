import {
  Injectable,
  inject,
  PLATFORM_ID,
  signal,
  WritableSignal,
} from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { HttpClient, HttpContext } from '@angular/common/http';
import { Observable, tap, throwError } from 'rxjs'; // Removed BehaviorSubject
import { jwtDecode, JwtPayload } from 'jwt-decode';
import { BYPASS_AUTH_INTERCEPTOR } from '@/auth/auth.interceptor';
import { environment } from '@/environments/environment';
import { Router } from '@angular/router';

@Injectable({
  providedIn: 'root',
})
export class AuthService {
  private http = inject(HttpClient);
  private platformId = inject(PLATFORM_ID);
  private router = inject(Router);

  private readonly isBrowser: boolean = isPlatformBrowser(this.platformId);

  private apiUrl = environment.apiUrl;
  private accessTokenKey = environment.tokenKey;
  private refreshTokenKey = environment.refreshTokenKey;

  /**
   * Signals-based state management for authentication status and company ID.
   * This replaces RxJS BehaviorSubjects/Observables with Angular signals.
   */
  private loggedInStatus: WritableSignal<boolean> = signal(
    this._hasValidAccessToken()
  );
  private currentCompanyId: WritableSignal<string | null> = signal(
    this._getUserCompanyIdFromToken()
  );

  constructor() {
    if (this.isBrowser) {
      this.loggedInStatus.set(this._hasValidAccessToken());
      this.currentCompanyId.set(this._getUserCompanyIdFromToken());
      // Optional: Listen to localStorage changes from other tabs (advanced)
    }
  }

  // Expose signals for state
  get isLoggedIn(): boolean {
    return this.loggedInStatus();
  }

  get isLoggedInSignal(): WritableSignal<boolean> {
    return this.loggedInStatus;
  }

  get currentCompanyIdValue(): string | null {
    return this.currentCompanyId();
  }

  get currentCompanyIdSignal(): WritableSignal<string | null> {
    return this.currentCompanyId;
  }

  login(credentials: { email: string; password: string }): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/auth/login`, credentials).pipe(
      tap((response) => {
        if (response && response.accessToken && response.refreshToken) {
          this._setTokens(response.accessToken, response.refreshToken);
        } else {
          console.error(
            'Login response did not include expected tokens:',
            response
          );
          this._clearTokensAndNotify();
        }
      })
    );
  }

  register(userInfo: any): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/auth/register`, userInfo);
  }

  logout(navigateLogin: boolean = true): void {
    this._clearTokensAndNotify();
    if (navigateLogin && this.isBrowser) {
      this.router.navigate(['/login']);
    }
  }

  refreshToken(): Observable<any> {
    const refreshToken = this._getRefreshToken();
    if (!refreshToken) {
      this.logout(true);
      return throwError(() => new Error('No refresh token available'));
    }
    return this.http
      .post<any>(
        `${this.apiUrl}/auth/refresh-token`,
        { refreshToken },
        { context: new HttpContext().set(BYPASS_AUTH_INTERCEPTOR, true) }
      )
      .pipe(
        tap((response) => {
          if (response && response.accessToken) {
            const newRefreshToken = response.newRefreshToken || refreshToken;
            this._setTokens(response.accessToken, newRefreshToken);
          } else {
            this.logout(true);
            throw new Error(
              'Refresh token endpoint did not return an access token.'
            );
          }
        })
      );
  }

  public updateTokens(accessToken: string, refreshToken?: string): void {
    const currentRefreshToken = refreshToken || this._getRefreshToken();
    if (!currentRefreshToken) {
      console.error('Cannot update tokens: Refresh token is missing.');
      this.logout(true);
      return;
    }
    this._setTokens(accessToken, currentRefreshToken);
  }

  resendVerification(email: string): Observable<any> {
    return this.http.post<any>(
      `${this.apiUrl}/auth/resend-verification-email`,
      { email }
    );
  }

  verifyEmailToken(token: string): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/auth/verify-email`, { token });
  }

  requestPasswordReset(email: string): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/auth/request-password-reset`, {
      email,
    });
  }

  resetPassword(token: string, newPassword: string): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/auth/reset-password`, {
      token,
      new_password: newPassword,
    });
  }

  private _getAccessToken(): string | null {
    if (this.isBrowser) {
      return localStorage.getItem(this.accessTokenKey);
    }
    return null;
  }

  private _getRefreshToken(): string | null {
    if (this.isBrowser) {
      return localStorage.getItem(this.refreshTokenKey);
    }
    return null;
  }

  public getAccessToken(): string | null {
    return this._getAccessToken();
  }

  isLoggedInLegacy(): boolean {
    // For legacy compatibility if needed
    return this._hasValidAccessToken();
  }

  public getUserCompanyId(): string | null {
    return this._getUserCompanyIdFromToken();
  }

  private _decodeToken(): (JwtPayload & HasuraClaims) | null {
    const token = this._getAccessToken();
    if (!token) return null;
    try {
      return jwtDecode<JwtPayload & HasuraClaims>(token);
    } catch (e) {
      console.error('Failed to decode token:', e);
      return null;
    }
  }

  private _getUserCompanyIdFromToken(): string | null {
    const decodedToken = this._decodeToken();
    return (
      decodedToken?.['https://hasura.io/jwt/claims']?.['x-hasura-company-id'] ||
      null
    );
  }

  private _hasValidAccessToken(): boolean {
    const decodedToken = this._decodeToken();
    if (!decodedToken || typeof decodedToken.exp === 'undefined') {
      return false;
    }
    const expirationDate = new Date(0);
    expirationDate.setUTCSeconds(decodedToken.exp);
    return expirationDate > new Date();
  }

  private _setTokens(accessToken: string, refreshToken: string): void {
    if (this.isBrowser) {
      localStorage.setItem(this.accessTokenKey, accessToken);
      localStorage.setItem(this.refreshTokenKey, refreshToken);
    }
    this.loggedInStatus.set(this._hasValidAccessToken());
    this.currentCompanyId.set(this._getUserCompanyIdFromToken());
  }

  private _clearTokensAndNotify(): void {
    if (this.isBrowser) {
      localStorage.removeItem(this.accessTokenKey);
      localStorage.removeItem(this.refreshTokenKey);
    }
    this.loggedInStatus.set(false);
    this.currentCompanyId.set(null);
  }
}

// Define an interface for the expected Hasura claims within the JWT
interface HasuraClaims {
  'https://hasura.io/jwt/claims'?: {
    'x-hasura-allowed-roles': string[];
    'x-hasura-default-role': string;
    'x-hasura-user-id': string;
    'x-hasura-company-id'?: string;
  };
  email?: string;
  first_name?: string;
}
