import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { of, throwError, Subject } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { provideNoopAnimations } from '@angular/platform-browser/animations';
import { provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';

import { LoginComponent } from './login.component';
import { AuthService } from '../auth.service';

import { vi, describe, it, expect, beforeEach, afterEach, Mock } from 'vitest';

describe('LoginComponent', () => {
  let component: LoginComponent;
  let fixture: ComponentFixture<LoginComponent>;
  let authService: AuthService;
  let router: Router;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [LoginComponent, ReactiveFormsModule],
      providers: [
        provideZonelessChangeDetection(),
        provideRouter([]),
        provideNoopAnimations(),
        {
          provide: AuthService,
          useValue: {
            login: vi.fn(),
            resendVerification: vi.fn(),
          },
        },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(LoginComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService);
    router = TestBed.inject(Router);
    vi.spyOn(router, 'navigate');
    fixture.detectChanges();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });

  describe('Form Validation', () => {
    it('should be invalid when empty', () => {
      expect(component.loginForm.valid).toBe(false);
    });

    it('should be invalid with only email', () => {
      component.loginForm.controls['email'].setValue('test@example.com');
      expect(component.loginForm.valid).toBe(false);
    });

    it('should be valid with email and password', () => {
      component.loginForm.controls['email'].setValue('test@example.com');
      component.loginForm.controls['password'].setValue('password123');
      expect(component.loginForm.valid).toBe(true);
    });
  });

  describe('Login Submission', () => {
    beforeEach(() => {
      component.loginForm.controls['email'].setValue('test@example.com');
      component.loginForm.controls['password'].setValue('password123');
    });

    it('should call authService.login and navigate on success', async () => {
      (authService.login as Mock).mockReturnValue(of({ success: true }));
      component.onSubmit();
      await fixture.whenStable();
      expect(authService.login).toHaveBeenCalledWith({
        email: 'test@example.com',
        password: 'password123',
      });
      expect(router.navigate).toHaveBeenCalledWith(['/dashboard']);
      expect(component.loginError()).toBeNull();
    });

    it('should display generic error on 401 failure', async () => {
      const error = new HttpErrorResponse({ status: 401 });
      (authService.login as Mock).mockReturnValue(throwError(() => error));
      component.onSubmit();
      await fixture.whenStable();
      expect(component.loginError()).toBe(
        'Invalid email or password. Please try again.'
      );
    });

    it('should show resend verification on 403 failure', async () => {
      const error = new HttpErrorResponse({ status: 403 });
      (authService.login as Mock).mockReturnValue(throwError(() => error));
      component.onSubmit();
      await fixture.whenStable();
      expect(component.loginError()).toBe(
        'Email not verified. Please check your email.'
      );
      expect(component.showResendVerification()).toBe(true);
    });

    it('should toggle isSubmitting signal', async () => {
      const loginSubject = new Subject<void>();
      (authService.login as Mock).mockReturnValue(loginSubject.asObservable());

      expect(component.isSubmitting()).toBe(false);
      component.onSubmit();
      expect(component.isSubmitting()).toBe(true); // Assert before observable completes

      loginSubject.next({ success: true } as any); // Simulate observable completion
      loginSubject.complete();

      await fixture.whenStable(); // Wait for finalize and other microtasks
      fixture.detectChanges();
      expect(component.isSubmitting()).toBe(false); // Assert final state
    });
  });

  describe('Resend Verification Email', () => {
    beforeEach(() => {
      component.loginForm.controls['email'].setValue('test@example.com');
      component.showResendVerification.set(true);
    });

    it('should call resendVerification and show success message', async () => {
      (authService.resendVerification as Mock).mockReturnValue(of({}));
      component.onResendVerificationEmail();
      await fixture.whenStable();
      expect(authService.resendVerification).toHaveBeenCalledWith(
        'test@example.com'
      );
      expect(component.resendVerificationMessage()).toBe(
        'A new verification email has been sent. Please check your inbox.'
      );
      expect(component.showResendVerification()).toBe(false);
    });

    it('should show error for invalid email', () => {
      component.loginForm.controls['email'].setValue('');
      component.onResendVerificationEmail();
      expect(authService.resendVerification).not.toHaveBeenCalled();
      expect(component.resendVerificationMessage()).toBe(
        'Please enter a valid email address.'
      );
    });

    it('should show specific error for 409 conflict', async () => {
      const error = new HttpErrorResponse({ status: 409 });
      (authService.resendVerification as Mock).mockReturnValue(
        throwError(() => error)
      );
      component.onResendVerificationEmail();
      await fixture.whenStable();
      expect(component.resendVerificationMessage()).toBe(
        'This email address has already been verified. You can try logging in.'
      );
    });

    it('should show generic error for other failures', async () => {
      const error = new HttpErrorResponse({ status: 500 });
      (authService.resendVerification as Mock).mockReturnValue(
        throwError(() => error)
      );
      component.onResendVerificationEmail();
      await fixture.whenStable();
      expect(component.resendVerificationMessage()).toBe(
        'Failed to resend verification email. Please try again later.'
      );
    });

    it('should toggle isResendingVerification signal', async () => {
      const resendSubject = new Subject<void>();
      (authService.resendVerification as Mock).mockReturnValue(resendSubject.asObservable());

      expect(component.isResendingVerification()).toBe(false);
      component.onResendVerificationEmail();
      expect(component.isResendingVerification()).toBe(true); // Assert before observable completes

      resendSubject.next(); // Simulate observable completion
      resendSubject.complete();

      await fixture.whenStable(); // Wait for finalize and other microtasks
      fixture.detectChanges();
      expect(component.isResendingVerification()).toBe(false); // Assert final state
    });
  });

  it('should toggle password visibility', () => {
    expect(component.hidePassword()).toBe(true);
    component.hidePassword.set(false);
    expect(component.hidePassword()).toBe(false);
  });
});
