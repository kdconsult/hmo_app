import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { ReactiveFormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { of, throwError } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { NoopAnimationsModule } from '@angular/platform-browser/animations';

import { ResetPasswordComponent } from './reset-password.component';
import { AuthService } from '../auth.service';
// Assuming password complexity constants/validators are correctly imported or mocked if needed
// For this test, we'll rely on the component's own import of them.
import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest'; // Import Vitest globals


// Material Modules
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatIconModule } from '@angular/material/icon';

class MockAuthService {
  resetPassword = vi.fn();
}

class MockRouter {
  navigate = vi.fn();
}

describe('ResetPasswordComponent', () => {
  let component: ResetPasswordComponent;
  let fixture: ComponentFixture<ResetPasswordComponent>;
  let authService: MockAuthService;
  let router: MockRouter;

  const mockToken = 'test-reset-token';

  const setupComponent = (queryParams: Record<string, string | null>) => {
    TestBed.configureTestingModule({
      imports: [
        ResetPasswordComponent, // Standalone
        ReactiveFormsModule,
        NoopAnimationsModule,
        MatCardModule, MatFormFieldModule, MatInputModule, MatButtonModule, MatProgressSpinnerModule, MatIconModule
      ],
      providers: [
        { provide: AuthService, useClass: MockAuthService },
        { provide: Router, useClass: MockRouter },
        {
          provide: ActivatedRoute,
          useValue: {
            queryParamMap: of(new Map(Object.entries(queryParams))),
          },
        },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(ResetPasswordComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService) as unknown as MockAuthService;
    router = TestBed.inject(Router) as unknown as MockRouter;
  };

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('should create', () => {
    setupComponent({ token: mockToken });
    fixture.detectChanges(); // ngOnInit
    expect(component).toBeTruthy();
  });

  it('should extract token on init and enable form if token exists', fakeAsync(() => {
    setupComponent({ token: mockToken });
    fixture.detectChanges(); // ngOnInit
    tick();
    expect(component['resetToken']).toBe(mockToken);
    expect(component.resetPasswordForm.enabled).toBe(true);
    expect(component.message()).toBeNull();
  }));

  it('should display error and disable form if token is missing', fakeAsync(() => {
    setupComponent({ token: null });
    fixture.detectChanges(); // ngOnInit
    tick();
    expect(component['resetToken']).toBeNull();
    expect(component.resetPasswordForm.disabled).toBe(true);
    expect(component.messageType()).toBe('error');
    expect(component.message()).toBe('Password reset token not found or invalid. Please request a new reset link.');
  }));

  describe('Form Validation', () => {
    beforeEach(() => {
        setupComponent({ token: mockToken });
        fixture.detectChanges();
    });

    it('should invalidate form with empty passwords', () => {
      component.resetPasswordForm.controls['newPassword'].setValue('');
      component.resetPasswordForm.controls['confirmNewPassword'].setValue('');
      expect(component.resetPasswordForm.valid).toBe(false);
    });

    it('should validate password complexity for newPassword', () => {
      component.resetPasswordForm.controls['newPassword'].setValue('weak');
      expect(component.newPasswordControl?.hasError('passwordMinLength')).toBe(true); // Example check
    });

    it('should validate password mismatch', () => {
      component.resetPasswordForm.controls['newPassword'].setValue('ValidP@ss1');
      component.resetPasswordForm.controls['confirmNewPassword'].setValue('ValidP@ss2');
      expect(component.resetPasswordForm.hasError('passwordsMismatch')).toBe(true);
    });

    it('should validate with valid, matching, complex passwords', () => {
      component.resetPasswordForm.controls['newPassword'].setValue('ValidP@ss123');
      component.resetPasswordForm.controls['confirmNewPassword'].setValue('ValidP@ss123');
      expect(component.resetPasswordForm.valid).toBe(true);
    });
  });

  describe('Submission', () => {
    const validPassword = 'ValidP@ss123';
    beforeEach(() => {
      setupComponent({ token: mockToken });
      fixture.detectChanges();
      component.resetPasswordForm.controls['newPassword'].setValue(validPassword);
      component.resetPasswordForm.controls['confirmNewPassword'].setValue(validPassword);
    });

    it('should call authService.resetPassword and navigate to login on success', fakeAsync(() => {
      authService.resetPassword.mockReturnValue(of({ message: 'Password reset' }));
      component.onSubmit();
      tick();

      expect(authService.resetPassword).toHaveBeenCalledWith(mockToken, validPassword);
      expect(component.messageType()).toBe('success');
      expect(component.message()).toBe('Password successfully reset. You will be redirected to login shortly.');
      expect(component.resetPasswordForm.disabled).toBe(true);

      tick(3000); // For setTimeout
      expect(router.navigate).toHaveBeenCalledWith(['/login']);
    }));

    it('should display error message on API failure (e.g., 400 invalid token)', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({ status: 400, error: { message: 'Token invalid' } });
      authService.resetPassword.mockReturnValue(throwError(() => errorResponse));
      component.onSubmit();
      tick();

      expect(authService.resetPassword).toHaveBeenCalledWith(mockToken, validPassword);
      expect(component.messageType()).toBe('error');
      expect(component.message()).toBe('Invalid or expired reset token. Please try requesting a new link.');
      expect(router.navigate).not.toHaveBeenCalled();
    }));

    it('should display generic error message for other API failures', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({ status: 500 });
      authService.resetPassword.mockReturnValue(throwError(() => errorResponse));
      component.onSubmit();
      tick();
      expect(component.message()).toBe('Failed to reset password.');
    }));


    it('should set isLoading to true during submission and false after', fakeAsync(() => {
      authService.resetPassword.mockReturnValue(of({}));
      expect(component.isLoading()).toBe(false);
      component.onSubmit();
      expect(component.isLoading()).toBe(true);
      tick();
      expect(component.isLoading()).toBe(false);
    }));

    it('should not submit if form is invalid and mark form as touched', () => {
      component.resetPasswordForm.controls['newPassword'].setValue('');
      const markSpy = jest.spyOn(component.resetPasswordForm, 'markAllAsTouched');
      component.onSubmit();
      expect(authService.resetPassword).not.toHaveBeenCalled();
      expect(markSpy).toHaveBeenCalled();
    });

    it('should not submit if token is missing (after init)', () => {
      component['resetToken'] = null; // Simulate token becoming null after init
      component.onSubmit();
      expect(authService.resetPassword).not.toHaveBeenCalled();
      expect(component.message()).toBe('Cannot reset password without a valid token.');
    });
  });

  it('should toggle password visibility for newPassword and confirmNewPassword', () => {
    setupComponent({ token: mockToken });
    fixture.detectChanges();

    expect(component.hidePassword()).toBe(true);
    component.hidePassword.set(!component.hidePassword());
    expect(component.hidePassword()).toBe(false);

    expect(component.hideConfirmPassword()).toBe(true);
    component.hideConfirmPassword.set(!component.hideConfirmPassword());
    expect(component.hideConfirmPassword()).toBe(false);
  });
});
