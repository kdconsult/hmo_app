import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { MatDialog } from '@angular/material/dialog';
import { of, throwError } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { provideNoopAnimations } from '@angular/platform-browser/animations';
import { provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { vi, describe, it, expect, beforeEach, afterEach, Mock } from 'vitest';

import { RegisterComponent } from './register.component';
import { AuthService } from '../auth.service';
import { TermsAndConditionsComponent } from '@/shared/components/terms-and-conditions/terms-and-conditions.component';

describe('RegisterComponent', () => {
  let component: RegisterComponent;
  let fixture: ComponentFixture<RegisterComponent>;
  let authService: AuthService;
  let dialog: MatDialog;
  let router: Router;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [RegisterComponent, ReactiveFormsModule],
      providers: [
        provideZonelessChangeDetection(),
        provideRouter([]),
        provideNoopAnimations(),
        {
          provide: AuthService,
          useValue: {
            register: vi.fn(),
          },
        },
        {
          provide: MatDialog,
          useValue: {
            open: vi.fn(),
          },
        },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(RegisterComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService);
    dialog = TestBed.inject(MatDialog);
    router = TestBed.inject(Router);
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
      expect(component.registerForm.valid).toBe(false);
    });

    it('should be invalid with password mismatch', () => {
      component.registerForm.controls['password'].setValue('ValidP@ss1');
      component.registerForm.controls['confirmPassword'].setValue(
        'DifferentP@ss1'
      );
      expect(component.registerForm.hasError('passwordsMismatch')).toBe(true);
    });

    it('should be invalid with a weak password', () => {
      component.registerForm.controls['password'].setValue('weak');
      expect(component.registerForm.controls['password'].invalid).toBe(true);
    });

    it('should be valid with all fields correct', () => {
      component.registerForm.patchValue({
        first_name: 'Test',
        last_name: 'User',
        email: 'test@example.com',
        password: 'ValidP@ss123',
        confirmPassword: 'ValidP@ss123',
        terms_agreed: true,
      });
      expect(component.registerForm.valid).toBe(true);
    });
  });

  describe('Registration Submission', () => {
    const validFormData = {
      first_name: 'Test',
      last_name: 'User',
      email: 'test@example.com',
      password: 'ValidP@ss123',
      confirmPassword: 'ValidP@ss123',
      terms_agreed: true,
    };

    beforeEach(() => {
      component.registerForm.setValue(validFormData);
    });

    it('should call authService.register and show success message', async () => {
      (authService.register as Mock).mockReturnValue(of({}));
      component.onSubmit();
      await fixture.whenStable();

      const { confirmPassword, ...payload } = validFormData;
      expect(authService.register).toHaveBeenCalledWith(payload);
      expect(component.registrationSuccessMessage()).toContain(
        'Registration successful!'
      );
      expect(component.registerForm.get('first_name')?.value).toBeNull();
    });

    it('should display error message on 409 conflict', async () => {
      const error = new HttpErrorResponse({ status: 409 });
      (authService.register as Mock).mockReturnValue(throwError(() => error));
      component.onSubmit();
      await fixture.whenStable();
      expect(component.registrationError()).toBe(
        'This email address is already in use. Please try another one or login.'
      );
    });

    it('should display generic error for other failures', async () => {
      const error = new HttpErrorResponse({ status: 500 });
      (authService.register as Mock).mockReturnValue(throwError(() => error));
      component.onSubmit();
      await fixture.whenStable();
      expect(component.registrationError()).toBe(
        'Registration failed due to an unexpected error. Please try again.'
      );
    });

    it('should toggle isSubmitting signal', async () => {
      (authService.register as Mock).mockReturnValue(
        throwError(() => new HttpErrorResponse({ status: 500 }))
      );
      expect(component.isSubmitting()).toBe(false);
      component.onSubmit();
      expect(component.isSubmitting()).toBe(true);
      await fixture.whenStable();
      expect(component.isSubmitting()).toBe(false);
    });
  });

  describe('Terms and Conditions Dialog', () => {
    it('should open MatDialog when openTermsDialog is called', () => {
      const mockEvent = { preventDefault: vi.fn() } as unknown as MouseEvent;
      component.openTermsDialog(mockEvent);
      expect(mockEvent.preventDefault).toHaveBeenCalled();
      expect(dialog.open).toHaveBeenCalledWith(TermsAndConditionsComponent, {
        width: '80vw',
        maxWidth: '800px',
        autoFocus: false,
      });
    });

    it('should patch terms_agreed to true if dialog is accepted', () => {
      (dialog.open as Mock).mockReturnValue({ afterClosed: () => of(true) });
      component.openTermsDialog(null as unknown as MouseEvent);
      expect(component.registerForm.controls['terms_agreed'].value).toBe(true);
    });

    it('should not change terms_agreed if dialog is dismissed', () => {
      component.registerForm.controls['terms_agreed'].setValue(false);
      (dialog.open as Mock).mockReturnValue({ afterClosed: () => of(false) });
      component.openTermsDialog(null as unknown as MouseEvent);
      expect(component.registerForm.controls['terms_agreed'].value).toBe(false);
    });
  });

  it('should toggle password visibility', () => {
    expect(component.hidePassword()).toBe(true);
    component.hidePassword.set(false);
    expect(component.hidePassword()).toBe(false);
  });
});
