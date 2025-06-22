import { Component, OnInit, inject, signal, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, Validators, ReactiveFormsModule, AbstractControl, ValidationErrors } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatIconModule } from '@angular/material/icon'; // For error/success icons and password visibility

import { AuthService } from '../auth.service';
import { passwordComplexityRules, passwordComplexityMessages, passwordComplexityValidator } from '../register/register.component'; // Re-use from register
import { finalize } from 'rxjs/operators';
import { of } from 'rxjs'; // for handling cases where token is missing

// Validator for matching passwords (can be moved to a shared validators file)
function passwordsMatchValidator(control: AbstractControl): ValidationErrors | null {
  const password = control.get('newPassword')?.value;
  const confirmPassword = control.get('confirmNewPassword')?.value;
  return password === confirmPassword ? null : { passwordsMismatch: true };
}

@Component({
  selector: 'app-reset-password',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    RouterModule,
    MatCardModule,
    MatFormFieldModule,
    MatInputModule,
    MatButtonModule,
    MatProgressSpinnerModule,
    MatIconModule,
  ],
  templateUrl: './reset-password.component.html',
  styleUrls: ['./reset-password.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ResetPasswordComponent implements OnInit {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);

  isLoading = signal(false);
  message = signal<string | null>(null);
  messageType = signal<'success' | 'error'>('error');
  hidePassword = signal(true);
  hideConfirmPassword = signal(true);

  private resetToken: string | null = null;

  // Expose to template
  public readonly passwordComplexityMessages = passwordComplexityMessages;

  resetPasswordForm = this.fb.group({
    newPassword: ['', [Validators.required, passwordComplexityValidator]],
    confirmNewPassword: ['', [Validators.required]],
  }, { validators: passwordsMatchValidator });

  ngOnInit(): void {
    this.route.queryParamMap.subscribe(params => {
      this.resetToken = params.get('token');
      if (!this.resetToken) {
        this.messageType.set('error');
        this.message.set('Password reset token not found or invalid. Please request a new reset link.');
        this.resetPasswordForm.disable(); // Disable form if no token
      }
    });
  }

  get newPasswordControl() {
    return this.resetPasswordForm.get('newPassword');
  }

  get confirmNewPasswordControl() {
    return this.resetPasswordForm.get('confirmNewPassword');
  }

  onSubmit(): void {
    if (this.resetPasswordForm.invalid) {
      this.resetPasswordForm.markAllAsTouched();
      return;
    }
    if (!this.resetToken) {
        this.messageType.set('error');
        this.message.set('Cannot reset password without a valid token.');
        return;
    }

    this.isLoading.set(true);
    this.message.set(null);
    const newPassword = this.newPasswordControl?.value;

    if (newPassword) {
      this.authService.resetPassword(this.resetToken, newPassword)
        .pipe(finalize(() => this.isLoading.set(false)))
        .subscribe({
          next: () => {
            this.messageType.set('success');
            this.message.set('Password successfully reset. You will be redirected to login shortly.');
            this.resetPasswordForm.reset();
            this.resetPasswordForm.disable();
            setTimeout(() => this.router.navigate(['/login']), 3000); // Redirect after 3s
          },
          error: (err) => {
            this.messageType.set('error');
            let errorMessage = 'Failed to reset password.';
            if (err.error && typeof err.error.message === 'string') {
              errorMessage = err.error.message;
            } else if (err.status === 400) {
                 errorMessage = 'Invalid or expired reset token. Please try requesting a new link.';
            }
            this.message.set(errorMessage);
          }
        });
    } else {
        this.isLoading.set(false);
        this.messageType.set('error');
        this.message.set('Please enter and confirm your new password.');
    }
  }
}
