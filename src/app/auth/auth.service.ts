import { Injectable, inject, PLATFORM_ID } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';
import { jwtDecode } from 'jwt-decode';
import { environment } from '@/environments/environment';

@Injectable({
  providedIn: 'root',
})
export class AuthService {
  private http = inject(HttpClient);
  private platformId = inject(PLATFORM_ID);

  private readonly isBrowser: boolean = isPlatformBrowser(this.platformId);

  private apiUrl = environment.apiUrl;
  private tokenKey = environment.tokenKey;

  login(credentials: { email: string; password: string }): Observable<any> {
    return this.http
      .post<any>(`${this.apiUrl}/login`, credentials)
      .pipe(tap((response) => this.setToken(response.token)));
  }

  register(userInfo: any): Observable<any> {
    return this.http
      .post<any>(`${this.apiUrl}/register`, userInfo)
      .pipe(tap((response) => this.setToken(response.token)));
  }

  logout(): void {
    if (this.isBrowser) {
      localStorage.removeItem(this.tokenKey);
    }
    // Here you might also want to navigate the user to the login page
    // or clear any other user-related state.
  }

  getToken(): string | null {
    if (this.isBrowser) {
      return localStorage.getItem(this.tokenKey);
    }
    return null;
  }

  isLoggedIn(): boolean {
    const token = this.getToken();

    if (!token) {
      return false;
    }

    try {
      const decodedToken = jwtDecode(token);
      const expirationDate = new Date(0);
      expirationDate.setUTCSeconds(decodedToken.exp as number);
      return expirationDate > new Date();
    } catch (e) {
      // If the token is invalid, we'll treat it as expired.
      return false;
    }
  }

  private setToken(token: string): void {
    if (this.isBrowser) {
      localStorage.setItem(this.tokenKey, token);
    }
  }
}
