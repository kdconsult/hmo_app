import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { MatDialog } from '@angular/material/dialog';
import { of, throwError } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { NoopAnimationsModule } from '@angular/platform-browser/animations';

import { RegisterComponent, passwordComplexityRules, passwordComplexityValidator } from './register.component';
import { AuthService } from '../auth.service';
import { TermsAndConditionsComponent } from '@/app/shared/components/terms-and-conditions/terms-and-conditions.component';

// Material Modules (imported by standalone RegisterComponent, but good to have for TestBed)
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatCheckboxModule } from '@angular/material/checkbox';
import { MatIconModule } from '@angular/material/icon';

class MockAuthService {
  register = jest.fn();
}

class MockRouter {
  navigate = jest.fn();
}

class MockMatDialog {
  open = jest.fn();
}

describe('RegisterComponent', () => {
  let component: RegisterComponent;
  let fixture: ComponentFixture<RegisterComponent>;
  let authService: MockAuthService;
  let router: MockRouter;
  let dialog: MockMatDialog;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [
        RegisterComponent, // Standalone component
        ReactiveFormsModule,
        NoopAnimationsModule,
        MatCardModule, MatFormFieldModule, MatInputModule, MatButtonModule, MatCheckboxModule, MatIconModule
      ],
      providers: [
        { provide: AuthService, useClass: MockAuthService },
        { provide: Router, useClass: MockRouter },
        { provide: MatDialog, useClass: MockMatDialog },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(RegisterComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService) as unknown as MockAuthService;
    router = TestBed.inject(Router) as unknown as MockRouter;
    dialog = TestBed.inject(MatDialog) as unknown as MockMatDialog;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });

  describe('Form Validation', () => {
    it('should invalidate form with empty required fields', () => {
      component.registerForm.controls['first_name'].setValue('');
      component.registerForm.controls['last_name'].setValue('');
      component.registerForm.controls['email'].setValue('');
      component.registerForm.controls['password'].setValue('');
      component.registerForm.controls['confirmPassword'].setValue('');
      component.registerForm.controls['terms_agreed'].setValue(false);
      expect(component.registerForm.valid).toBe(false);
    });

    it('should validate first_name and last_name as required', () => {
        component.registerForm.controls['first_name'].setValue('');
        expect(component.registerForm.controls['first_name'].hasError('required')).toBe(true);
        component.registerForm.controls['last_name'].setValue('');
        expect(component.registerForm.controls['last_name'].hasError('required')).toBe(true);
    });

    it('should validate email format', () => {
      component.registerForm.controls['email'].setValue('invalid');
      expect(component.registerForm.controls['email'].hasError('email')).toBe(true);
    });

    it('should validate terms_agreed checkbox as requiredTrue', () => {
      component.registerForm.controls['terms_agreed'].setValue(false);
      expect(component.registerForm.controls['terms_agreed'].hasError('requiredTrue')).toBe(true);
      component.registerForm.controls['terms_agreed'].setValue(true);
      expect(component.registerForm.controls['terms_agreed'].valid).toBe(true);
    });

    describe('Password Validation', () => {
      it('should require password', () => {
        component.registerForm.controls['password'].setValue('');
        expect(component.registerForm.controls['password'].hasError('required')).toBe(true);
      });

      it('should validate password complexity - minLength', () => {
        component.registerForm.controls['password'].setValue('Short1!');
        expect(component.registerForm.controls['password'].hasError('passwordMinLength')).toBe(true);
      });

      it('should validate password complexity - requireUppercase', () => {
        component.registerForm.controls['password'].setValue('nouppercase1!');
        expect(component.registerForm.controls['password'].hasError('passwordUppercase')).toBe(true);
      });
      it('should validate password complexity - requireLowercase', () => {
        component.registerForm.controls['password'].setValue('NOLOWERCASE1!');
        expect(component.registerForm.controls['password'].hasError('passwordLowercase')).toBe(true);
      });
      it('should validate password complexity - requireNumeric', () => {
        component.registerForm.controls['password'].setValue('NoNumericHere!');
        expect(component.registerForm.controls['password'].hasError('passwordNumeric')).toBe(true);
      });
      it('should validate password complexity - requireSpecialChar', () => {
        component.registerForm.controls['password'].setValue('NoSpecialChar1');
        expect(component.registerForm.controls['password'].hasError('passwordSpecialChar')).toBe(true);
      });

      it('should validate a complex password correctly', () => {
        component.registerForm.controls['password'].setValue('ComplexP@ss1');
        expect(component.registerForm.controls['password'].valid).toBe(true);
      });

      it('should validate password confirmation match', () => {
        component.registerForm.controls['password'].setValue('ComplexP@ss1');
        component.registerForm.controls['confirmPassword'].setValue('ComplexP@ss2');
        expect(component.registerForm.hasError('passwordsMismatch')).toBe(true);
      });

       it('should validate password confirmation as required', () => {
        component.registerForm.controls['confirmPassword'].setValue('');
        expect(component.registerForm.controls['confirmPassword'].hasError('required')).toBe(true);
      });
    });

    it('should validate the form with all valid inputs', () => {
      component.registerForm.controls['first_name'].setValue('Test');
      component.registerForm.controls['last_name'].setValue('User');
      component.registerForm.controls['email'].setValue('test@example.com');
      component.registerForm.controls['password'].setValue('ValidP@ss123');
      component.registerForm.controls['confirmPassword'].setValue('ValidP@ss123');
      component.registerForm.controls['terms_agreed'].setValue(true);
      expect(component.registerForm.valid).toBe(true);
    });
  });

  describe('Registration Submission', () => {
    const validFormData = {
      first_name: 'Test',
      last_name: 'User',
      email: 'test@example.com',
      password: 'ValidP@ss123',
      terms_agreed: true
    };
    const rawFormValue = { ...validFormData, confirmPassword: 'ValidP@ss123' };


    beforeEach(() => {
      component.registerForm.setValue(rawFormValue);
    });

    it('should call authService.register and display success message', fakeAsync(() => {
      authService.register.mockReturnValue(of({ message: 'Registration successful' }));
      component.onSubmit();
      tick();

      const { confirmPassword, ...expectedPayload } = rawFormValue; // Exclude confirmPassword
      expect(authService.register).toHaveBeenCalledWith(expectedPayload);
      expect(component.registrationSuccessMessage()).toBe(
        `Registration successful! Please check your email (${validFormData.email}) to verify your account.`
      );
      expect(component.registrationError()).toBeNull();
      expect(component.registerForm.disabled).toBe(false); // Form should be reset, not disabled unless intended
      // Check if form is reset
      expect(component.registerForm.controls['first_name'].value).toBeNull();
    }));

    it('should display 409 error message if email already exists', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({ status: 409, error: { message: 'Email exists' } });
      authService.register.mockReturnValue(throwError(() => errorResponse));
      component.onSubmit();
      tick();
      expect(authService.register).toHaveBeenCalled();
      expect(component.registrationError()).toBe('This email address is already in use. Please try another one or login.');
      expect(component.registrationSuccessMessage()).toBeNull();
    }));

    it('should display generic error message on other registration failures', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({ status: 500, error: { message: 'Server error' } });
      authService.register.mockReturnValue(throwError(() => errorResponse));
      component.onSubmit();
      tick();
      expect(authService.register).toHaveBeenCalled();
      expect(component.registrationError()).toBe('Registration failed: Server error');
      expect(component.registrationSuccessMessage()).toBeNull();
    }));

    it('should display very generic error if no specific message from backend', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({ status: 500 }); // No error.message
      authService.register.mockReturnValue(throwError(() => errorResponse));
      component.onSubmit();
      tick();
      expect(component.registrationError()).toBe('Registration failed due to an unexpected error. Please try again.');
    }));


    it('should set isSubmitting to true during registration and false after', fakeAsync(() => {
      authService.register.mockReturnValue(of({}));
      expect(component.isSubmitting()).toBe(false);
      component.onSubmit();
      expect(component.isSubmitting()).toBe(true);
      tick();
      expect(component.isSubmitting()).toBe(false);
    }));

     it('should mark all fields as touched if form is invalid on submit', () => {
      component.registerForm.reset(); // make form invalid
      const markAllAsTouchedSpy = jest.spyOn(component.registerForm, 'markAllAsTouched');
      component.onSubmit();
      expect(markAllAsTouchedSpy).toHaveBeenCalled();
    });

  });

  describe('Terms and Conditions Dialog', () => {
    it('should open TermsAndConditionsComponent dialog', () => {
      const mockEvent = { preventDefault: jest.fn() } as unknown as MouseEvent;
      component.openTermsDialog(mockEvent);
      expect(mockEvent.preventDefault).toHaveBeenCalled();
      expect(dialog.open).toHaveBeenCalledWith(TermsAndConditionsComponent, {
        width: '80vw',
        maxWidth: '800px',
        autoFocus: false,
      });
    });
  });

  it('should toggle password visibility', () => {
    expect(component.hidePassword()).toBe(true);
    component.hidePassword.set(!component.hidePassword());
    expect(component.hidePassword()).toBe(false);
  });

});
