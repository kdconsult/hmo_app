import {
  Component,
  ChangeDetectionStrategy,
  inject,
  signal,
} from '@angular/core';
import {
  AbstractControl,
  FormBuilder,
  Validators,
  ReactiveFormsModule,
  ValidationErrors,
} from '@angular/forms';
import { RouterModule } from '@angular/router';
import { finalize } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http'; // Correctly placed import

import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatCheckboxModule } from '@angular/material/checkbox';
import { MatDialog, MatDialogModule } from '@angular/material/dialog';

import { AuthService } from '../auth.service';
import { TermsAndConditionsComponent } from '@/shared/components/terms-and-conditions/terms-and-conditions.component';

// Password Complexity Rules
export const passwordComplexityRules = {
  minLength: 8,
  requireUppercase: true,
  requireLowercase: true,
  requireNumeric: true,
  requireSpecialChar: true,
};

export const passwordComplexityMessages = {
  minLength: `Minimum ${passwordComplexityRules.minLength} characters`,
  requireUppercase: 'At least one uppercase letter',
  requireLowercase: 'At least one lowercase letter',
  requireNumeric: 'At least one number',
  requireSpecialChar: 'At least one special character (e.g., !@#$%^&*)',
};

// Custom Validators
function passwordsMatchValidator(
  control: AbstractControl
): ValidationErrors | null {
  const password = control.get('password')?.value;
  const confirmPassword = control.get('confirmPassword')?.value;
  return password === confirmPassword ? null : { passwordsMismatch: true };
}

export function passwordComplexityValidator(
  control: AbstractControl
): ValidationErrors | null {
  const password = control.value;
  if (!password) {
    return null; // Don't validate if there is no password
  }

  const errors: ValidationErrors = {};

  if (password.length < passwordComplexityRules.minLength) {
    errors['passwordMinLength'] = true;
  }
  if (passwordComplexityRules.requireUppercase && !/[A-Z]/.test(password)) {
    errors['passwordUppercase'] = true;
  }
  if (passwordComplexityRules.requireLowercase && !/[a-z]/.test(password)) {
    errors['passwordLowercase'] = true;
  }
  if (passwordComplexityRules.requireNumeric && !/\d/.test(password)) {
    errors['passwordNumeric'] = true;
  }
  if (
    passwordComplexityRules.requireSpecialChar &&
    !/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]+/.test(password)
  ) {
    errors['passwordSpecialChar'] = true;
  }

  return Object.keys(errors).length > 0 ? errors : null;
}

@Component({
  selector: 'app-register',
  imports: [
    RouterModule,
    ReactiveFormsModule,
    MatCardModule,
    MatFormFieldModule,
    MatInputModule,
    MatButtonModule,
    MatIconModule,
    MatCheckboxModule,
    MatDialogModule, // Required for MatDialog service
  ],
  templateUrl: './register.component.html',
  styleUrl: './register.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class RegisterComponent {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private dialog = inject(MatDialog);

  hidePassword = signal(true);
  registrationError = signal<string | null>(null);
  registrationSuccessMessage = signal<string | null>(null); // For success message
  isSubmitting = signal(false);

  // Expose to template
  passwordComplexityMessages = passwordComplexityMessages;

  registerForm = this.fb.group(
    {
      first_name: ['', [Validators.required]],
      last_name: ['', [Validators.required]],
      email: ['', [Validators.required, Validators.email]],
      password: ['', [Validators.required, passwordComplexityValidator]],
      confirmPassword: ['', [Validators.required]],
      terms_agreed: [false, [Validators.requiredTrue]],
    },
    { validators: passwordsMatchValidator }
  );

  onSubmit(): void {
    if (this.registerForm.invalid) {
      // Mark all fields as touched to display errors
      this.registerForm.markAllAsTouched();
      return;
    }

    this.isSubmitting.set(true);
    this.registrationError.set(null);
    this.registrationSuccessMessage.set(null);

    // We can omit confirmPassword from the value sent to the backend
    const { first_name, last_name, email, password, terms_agreed } =
      this.registerForm.getRawValue();

    // Ensure email is not null before using it in the success message.
    const userEmail = email || '';

    if (first_name && last_name && email && password && terms_agreed) {
      this.authService
        .register({ first_name, last_name, email, password, terms_agreed })
        .pipe(finalize(() => this.isSubmitting.set(false)))
        .subscribe({
          next: () => {
            this.registrationSuccessMessage.set(
              `Registration successful! Please check your email (${userEmail}) to verify your account.`
            );
            this.registerForm.reset(); // Reset form on success
            // Do not navigate immediately, let the user see the message.
            // Navigation to login can be offered on the verify-email-status page later.
          },
          error: (err: HttpErrorResponse) => {
            if (err.status === 409) {
              this.registrationError.set(
                'This email address is already in use. Please try another one or login.'
              );
            } else if (err.error && err.error.message) {
              // If backend provides a specific message
              this.registrationError.set(
                `Registration failed: ${err.error.message}`
              );
            } else {
              this.registrationError.set(
                'Registration failed due to an unexpected error. Please try again.'
              );
            }
          },
        });
    } else {
      // Fallback if somehow form is valid but values are not extracted (should not happen with proper validation)
      this.isSubmitting.set(false);
      this.registrationError.set(
        'Please ensure all fields are filled correctly.'
      );
    }
  }

  openTermsDialog(event: MouseEvent | null): void {
    event?.preventDefault(); // Prevent navigation if it's a real link and event exists
    this.dialog.open(TermsAndConditionsComponent, {
      width: '80vw', // Responsive width
      maxWidth: '800px', // Max width
      autoFocus: false, // Avoid focusing on the first focusable element
    });
  }
}
