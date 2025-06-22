import { Injectable, inject, PLATFORM_ID } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { HttpClient, HttpContext } from '@angular/common/http';
import { Observable, tap, BehaviorSubject, throwError } from 'rxjs'; // Added BehaviorSubject and throwError
import { jwtDecode, JwtPayload } from 'jwt-decode'; // Import JwtPayload
import { BYPASS_AUTH_INTERCEPTOR } from './auth.interceptor';
import { environment } from '@/environments/environment'; // Standardized path alias
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

  private loggedInStatus = new BehaviorSubject<boolean>(this._hasValidAccessToken());
  // Emits the company ID from token, or null if not present/not logged in
  private currentCompanyId = new BehaviorSubject<string | null>(this._getUserCompanyIdFromToken());


  constructor() {
    if (this.isBrowser) {
      this.loggedInStatus.next(this._hasValidAccessToken());
      this.currentCompanyId.next(this._getUserCompanyIdFromToken());
      // Optional: Listen to localStorage changes from other tabs (advanced)
    }
  }

  get isLoggedIn$(): Observable<boolean> {
    return this.loggedInStatus.asObservable();
  }

  get currentCompanyId$(): Observable<string | null> {
    return this.currentCompanyId.asObservable();
  }


  login(credentials: { email: string; password: string }): Observable<any> {
    return this.http
      .post<any>(`${this.apiUrl}/auth/login`, credentials)
      .pipe(
        tap((response) => {
          if (response && response.accessToken && response.refreshToken) {
            this._setTokens(response.accessToken, response.refreshToken);
          } else {
            console.error('Login response did not include expected tokens:', response);
            this._clearTokensAndNotify(); // Clear any partial state and notify
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
      this.logout(true); // No refresh token, force logout and navigate
      return throwError(() => new Error('No refresh token available'));
    }

    // Import HttpContext and BYPASS_AUTH_INTERCEPTOR if not already
    // import { HttpContext } from '@angular/common/http';
    // import { BYPASS_AUTH_INTERCEPTOR } from './auth.interceptor'; // Adjust path as needed

    return this.http.post<any>(
      `${this.apiUrl}/auth/refresh-token`,
      { refreshToken },
      { context: new HttpContext().set(BYPASS_AUTH_INTERCEPTOR, true) } // Bypass interceptor for this call
    )
      .pipe(
        tap((response) => {
          if (response && response.accessToken) {
            // Use new refresh token if backend provides it (for rotation)
            const newRefreshToken = response.newRefreshToken || refreshToken;
            this._setTokens(response.accessToken, newRefreshToken);
          } else {
            this.logout(true); // If no new access token, logout
            throw new Error('Refresh token endpoint did not return an access token.');
          }
        }),
      );
  }

  // Call this method after company creation if the backend returns new/updated tokens
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
    return this.http.post<any>(`${this.apiUrl}/auth/resend-verification-email`, { email });
  }

  verifyEmailToken(token: string): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/auth/verify-email`, { token });
  }

  requestPasswordReset(email: string): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/auth/request-password-reset`, { email });
  }

  resetPassword(token: string, newPassword: string): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/auth/reset-password`, { token, new_password: newPassword });
  }

  // Renamed with underscore to indicate private-like usage for internal state updates
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

  // Public getter for access token, e.g. for interceptor
  public getAccessToken(): string | null {
    return this._getAccessToken();
  }


  isLoggedIn(): boolean {
    return this._hasValidAccessToken();
  }

  // Method to get company ID from token
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
    return decodedToken?.['https://hasura.io/jwt/claims']?.['x-hasura-company-id'] || null;
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
    this.loggedInStatus.next(this._hasValidAccessToken());
    this.currentCompanyId.next(this._getUserCompanyIdFromToken());
  }

  private _clearTokensAndNotify(): void {
    if (this.isBrowser) {
      localStorage.removeItem(this.accessTokenKey);
      localStorage.removeItem(this.refreshTokenKey);
    }
    this.loggedInStatus.next(false);
    this.currentCompanyId.next(null);
  }
}

// Define an interface for the expected Hasura claims within the JWT
interface HasuraClaims {
  'https://hasura.io/jwt/claims'?: {
    'x-hasura-allowed-roles': string[];
    'x-hasura-default-role': string;
    'x-hasura-user-id': string;
    'x-hasura-company-id'?: string; // Optional, as it might not be present initially
    // Add other custom claims from Hasura if needed
  };
  // other top-level claims if any (e.g. email, first_name)
  email?: string;
  first_name?: string;
}
