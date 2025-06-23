import {
  ComponentFixture,
  TestBed,
  fakeAsync,
  tick,
} from '@angular/core/testing';
import { ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router'; // Though not used for navigation, good for consistency
import { of, throwError } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';

import { RequestPasswordResetComponent } from './request-password-reset.component';
import { AuthService } from '../auth.service';

import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest'; // Import Vitest globals

// Material Modules
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatIconModule } from '@angular/material/icon';

class MockAuthService {
  requestPasswordReset = vi.fn();
}

class MockRouter {} // Minimal mock as router isn't actively used by this component for navigation

describe('RequestPasswordResetComponent', () => {
  let component: RequestPasswordResetComponent;
  let fixture: ComponentFixture<RequestPasswordResetComponent>;
  let authService: MockAuthService;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [
        RequestPasswordResetComponent, // Standalone
        ReactiveFormsModule,
        MatCardModule,
        MatFormFieldModule,
        MatInputModule,
        MatButtonModule,
        MatProgressSpinnerModule,
        MatIconModule,
      ],
      providers: [
        { provide: AuthService, useClass: MockAuthService },
        { provide: Router, useClass: MockRouter }, // Provide mock even if not heavily used
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(RequestPasswordResetComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService) as unknown as MockAuthService;
    fixture.detectChanges();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });

  describe('Form Validation', () => {
    it('should invalidate the form when email is empty', () => {
      component.requestResetForm.controls['email'].setValue('');
      expect(component.requestResetForm.valid).toBe(false);
    });

    it('should invalidate the form when email is invalid', () => {
      component.requestResetForm.controls['email'].setValue('invalidemail');
      expect(
        component.requestResetForm.controls['email'].hasError('email')
      ).toBe(true);
      expect(component.requestResetForm.valid).toBe(false);
    });

    it('should validate the form with a valid email', () => {
      component.requestResetForm.controls['email'].setValue('test@example.com');
      expect(component.requestResetForm.valid).toBe(true);
    });
  });

  describe('Submission', () => {
    const testEmail = 'test@example.com';

    beforeEach(() => {
      component.requestResetForm.controls['email'].setValue(testEmail);
    });

    it('should call authService.requestPasswordReset and display generic success message on API success', fakeAsync(() => {
      authService.requestPasswordReset.mockReturnValue(
        of({ message: 'Reset link sent' })
      );
      component.onSubmit();
      tick();

      expect(authService.requestPasswordReset).toHaveBeenCalledWith(testEmail);
      expect(component.messageType()).toBe('success');
      expect(component.message()).toBe(
        `If an account exists for ${testEmail}, a password reset link has been sent. Please check your email.`
      );
      expect(component.requestResetForm.controls['email'].value).toBeNull(); // Form should be reset
    }));

    it('should call authService.requestPasswordReset and display generic success message even on API error', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({
        status: 500,
        error: { message: 'Server error' },
      });
      authService.requestPasswordReset.mockReturnValue(
        throwError(() => errorResponse)
      );
      const consoleErrorSpy = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {}); // Suppress console.error for this test

      component.onSubmit();
      tick();

      expect(authService.requestPasswordReset).toHaveBeenCalledWith(testEmail);
      expect(component.messageType()).toBe('success'); // Still success as per BLA
      expect(component.message()).toBe(
        `If an account exists for ${testEmail}, a password reset link has been sent. Please check your email.`
      );
      expect(component.requestResetForm.controls['email'].value).toBeNull(); // Form should be reset
      expect(consoleErrorSpy).toHaveBeenCalled(); // Check that the error was logged
      consoleErrorSpy.mockRestore();
    }));

    it('should set isLoading to true during submission and false after', fakeAsync(() => {
      authService.requestPasswordReset.mockReturnValue(of({}));
      expect(component.isLoading()).toBe(false);
      component.onSubmit();
      expect(component.isLoading()).toBe(true);
      tick();
      expect(component.isLoading()).toBe(false);
    }));

    it('should not submit if form is invalid and mark form as touched', () => {
      component.requestResetForm.controls['email'].setValue('');
      const markAllAsTouchedSpy = vi.spyOn(
        component.requestResetForm,
        'markAllAsTouched'
      );
      component.onSubmit();

      expect(authService.requestPasswordReset).not.toHaveBeenCalled();
      expect(markAllAsTouchedSpy).toHaveBeenCalled();
    });

    it('should display error message if email control is empty on submit (edge case, form should be invalid)', () => {
      component.requestResetForm.controls['email'].setValue(null); // or ''
      // Manually make the form valid to bypass the initial check, to test the internal `if (email)`
      Object.defineProperty(component.requestResetForm, 'invalid', {
        get: () => false,
      });

      component.onSubmit();
      expect(component.messageType()).toBe('error');
      expect(component.message()).toBe('Please enter a valid email address.');
      expect(authService.requestPasswordReset).not.toHaveBeenCalled();
    });
  });
});
