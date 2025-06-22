import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { of, throwError } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { NoopAnimationsModule } from '@angular/platform-browser/animations'; // For Material components

import { LoginComponent } from './login.component';
import { AuthService } from '../auth.service';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner'; // Added

import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest'; // Import Vitest globals

// Mock AuthService
class MockAuthService {
  login = vi.fn();
  resendVerification = vi.fn();
}

// Mock Router
class MockRouter {
  navigate = vi.fn();
}

describe('LoginComponent', () => {
  let component: LoginComponent;
  let fixture: ComponentFixture<LoginComponent>;
  let authService: MockAuthService;
  let router: MockRouter;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [
        LoginComponent, // LoginComponent already imports its necessary modules as it's standalone
        ReactiveFormsModule,
        NoopAnimationsModule, // Handles animations for Material components
        // Explicitly import Material modules used by the component's template for testing if not done by standalone import
        MatCardModule,
        MatFormFieldModule,
        MatInputModule,
        MatButtonModule,
        MatIconModule,
        MatProgressSpinnerModule
      ],
      providers: [
        { provide: AuthService, useClass: MockAuthService },
        { provide: Router, useClass: MockRouter },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(LoginComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService) as unknown as MockAuthService;
    router = TestBed.inject(Router) as unknown as MockRouter;
    fixture.detectChanges(); // Initial data binding
  });

  afterEach(() => {
    vi.clearAllMocks(); // Clear all Vitest mocks after each test
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });

  describe('Form Validation', () => {
    it('should invalidate the form when email is empty', () => {
      component.loginForm.controls['email'].setValue('');
      expect(component.loginForm.controls['email'].valid).toBe(false);
      expect(component.loginForm.valid).toBe(false);
    });

    it('should invalidate the form when email is invalid', () => {
      component.loginForm.controls['email'].setValue('invalidemail');
      expect(component.loginForm.controls['email'].valid).toBe(false);
    });

    it('should invalidate the form when password is empty', () => {
      component.loginForm.controls['password'].setValue('');
      expect(component.loginForm.controls['password'].valid).toBe(false);
      expect(component.loginForm.valid).toBe(false);
    });

    it('should validate the form with valid email and password', () => {
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

    it('should call authService.login and navigate to dashboard on successful login', fakeAsync(() => {
      authService.login.mockReturnValue(of({ success: true }));
      component.onSubmit();
      tick(); // Simulate passage of time for async operations
      expect(authService.login).toHaveBeenCalledWith({
        email: 'test@example.com',
        password: 'password123',
      });
      expect(router.navigate).toHaveBeenCalledWith(['/dashboard']);
      expect(component.loginError()).toBeNull();
    }));

    it('should display generic error message on login failure (e.g., 401)', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({ status: 401, error: { message: 'Invalid credentials' } });
      authService.login.mockReturnValue(throwError(() => errorResponse));
      component.onSubmit();
      tick();
      expect(authService.login).toHaveBeenCalled();
      expect(router.navigate).not.toHaveBeenCalled();
      expect(component.loginError()).toBe('Invalid email or password. Please try again.');
      expect(component.showResendVerification()).toBe(false);
    }));

    it('should display "Email not verified" message and show resend button on 403 error', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({ status: 403, error: { message: 'Email not verified' } });
      authService.login.mockReturnValue(throwError(() => errorResponse));
      component.onSubmit();
      tick();
      expect(authService.login).toHaveBeenCalled();
      expect(router.navigate).not.toHaveBeenCalled();
      expect(component.loginError()).toBe('Email not verified. Please check your email.');
      expect(component.showResendVerification()).toBe(true);

      // Check if resend button is visible (simplified DOM check)
      fixture.detectChanges(); // Update view
      const buttonElement = fixture.nativeElement.querySelector('.resend-button');
      expect(buttonElement).toBeTruthy();
    }));

     it('should set isSubmitting to true during login and false after', fakeAsync(() => {
      authService.login.mockReturnValue(of({ success: true }));
      expect(component.isSubmitting()).toBe(false);
      component.onSubmit();
      expect(component.isSubmitting()).toBe(true);
      tick();
      expect(component.isSubmitting()).toBe(false);
    }));

  });

  describe('Resend Verification Email', () => {
    beforeEach(() => {
      component.loginForm.controls['email'].setValue('test@example.com');
      // Simulate the scenario where the resend button is shown
      component.showResendVerification.set(true);
      fixture.detectChanges();
    });

    it('should call authService.resendVerification on onResendVerificationEmail()', fakeAsync(() => {
      authService.resendVerification.mockReturnValue(of({ message: 'Verification sent' }));
      component.onResendVerificationEmail();
      tick();
      expect(authService.resendVerification).toHaveBeenCalledWith('test@example.com');
      expect(component.resendVerificationMessage()).toBe('A new verification email has been sent. Please check your inbox.');
      expect(component.showResendVerification()).toBe(false); // Optionally hide after success
    }));

    it('should display error if email is invalid for resendVerification', () => {
      component.loginForm.controls['email'].setValue('invalid');
      component.onResendVerificationEmail();
      expect(authService.resendVerification).not.toHaveBeenCalled();
      expect(component.resendVerificationMessage()).toBe('Please enter a valid email address.');
    });

    it('should display error from authService.resendVerification on failure (e.g. already verified 409)', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({ status: 409, error: { message: 'Email already verified' } });
      authService.resendVerification.mockReturnValue(throwError(() => errorResponse));
      component.onResendVerificationEmail();
      tick();
      expect(authService.resendVerification).toHaveBeenCalled();
      expect(component.resendVerificationMessage()).toBe('This email address has already been verified. You can try logging in.');
    }));

    it('should display generic error from authService.resendVerification on other failure', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({ status: 500 });
      authService.resendVerification.mockReturnValue(throwError(() => errorResponse));
      component.onResendVerificationEmail();
      tick();
      expect(authService.resendVerification).toHaveBeenCalled();
      expect(component.resendVerificationMessage()).toBe('Failed to resend verification email. Please try again later.');
    }));

    it('should set isResendingVerification to true during resend and false after', fakeAsync(() => {
      authService.resendVerification.mockReturnValue(of({}));
      expect(component.isResendingVerification()).toBe(false);
      component.onResendVerificationEmail();
      expect(component.isResendingVerification()).toBe(true);
      tick();
      expect(component.isResendingVerification()).toBe(false);
    }));

  });

   it('should toggle password visibility', () => {
    expect(component.hidePassword()).toBe(true);
    component.hidePassword.set(!component.hidePassword());
    expect(component.hidePassword()).toBe(false);
  });

});
