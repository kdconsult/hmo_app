import {
  ComponentFixture,
  TestBed,
  TestBed,
} from '@angular/core/testing';
import { ReactiveFormsModule } from '@angular/forms';
import { Router, provideRouter } from '@angular/router';
import { of, throwError } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { provideNoopAnimations } from '@angular/platform-browser/animations';
import { provideZonelessChangeDetection } from '@angular/core';

import { RequestPasswordResetComponent } from './request-password-reset.component';
import { AuthService } from '../auth.service';

import { vi, describe, it, expect, beforeEach, afterEach, Mock } from 'vitest'; // Import Vitest globals

// Material Modules
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatIconModule } from '@angular/material/icon';

describe('RequestPasswordResetComponent', () => {
  let component: RequestPasswordResetComponent;
  let fixture: ComponentFixture<RequestPasswordResetComponent>;
  let authService: AuthService; // Changed type
  let router: Router; // Added router

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
        provideZonelessChangeDetection(),
        provideRouter([]),
        provideNoopAnimations(),
        {
          provide: AuthService,
          useValue: {
            requestPasswordReset: vi.fn(),
          },
        },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(RequestPasswordResetComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService);
    router = TestBed.inject(Router); // Inject router
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

    it('should call authService.requestPasswordReset and display generic success message on API success', async () => {
      (authService.requestPasswordReset as Mock).mockReturnValue(
        of({ message: 'Reset link sent' })
      );
      component.onSubmit();
      await fixture.whenStable();
      fixture.detectChanges();

      expect(authService.requestPasswordReset).toHaveBeenCalledWith(testEmail);
      expect(component.messageType()).toBe('success');
      expect(component.message()).toBe(
        `If an account exists for ${testEmail}, a password reset link has been sent. Please check your email.`
      );
      expect(component.requestResetForm.controls['email'].value).toBeNull(); // Form should be reset
    });

    it('should call authService.requestPasswordReset and display generic success message even on API error', async () => {
      const errorResponse = new HttpErrorResponse({
        status: 500,
        error: { message: 'Server error' },
      });
      (authService.requestPasswordReset as Mock).mockReturnValue(
        throwError(() => errorResponse)
      );
      const consoleErrorSpy = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {}); // Suppress console.error for this test

      component.onSubmit();
      await fixture.whenStable();
      fixture.detectChanges();

      expect(authService.requestPasswordReset).toHaveBeenCalledWith(testEmail);
      expect(component.messageType()).toBe('success'); // Still success as per BLA
      expect(component.message()).toBe(
        `If an account exists for ${testEmail}, a password reset link has been sent. Please check your email.`
      );
      expect(component.requestResetForm.controls['email'].value).toBeNull(); // Form should be reset
      expect(consoleErrorSpy).toHaveBeenCalled(); // Check that the error was logged
      consoleErrorSpy.mockRestore();
    });

    it('should set isLoading to true during submission and false after', async () => {
      (authService.requestPasswordReset as Mock).mockReturnValue(of({}));
      expect(component.isLoading()).toBe(false);
      component.onSubmit();
      expect(component.isLoading()).toBe(true);
      await fixture.whenStable();
      fixture.detectChanges();
      expect(component.isLoading()).toBe(false);
    });

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
