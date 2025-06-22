import {
  Component,
  ChangeDetectionStrategy,
  inject,
  signal,
} from '@angular/core';
import { FormBuilder, Validators, ReactiveFormsModule } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { CommonModule } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';

import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';


import { AuthService } from '../auth.service';
import { finalize } from 'rxjs';

@Component({
  selector: 'app-login',
  imports: [
    CommonModule,
    RouterModule,
    ReactiveFormsModule,
    MatCardModule,
    MatFormFieldModule,
    MatInputModule,
    MatButtonModule,
    MatIconModule,
    MatProgressSpinnerModule,
  ],
  templateUrl: './login.component.html',
  styleUrl: './login.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class LoginComponent {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);

  hidePassword = signal(true);
  loginError = signal<string | null>(null);
  isSubmitting = signal(false);
  showResendVerification = signal(false);
  resendVerificationMessage = signal<string | null>(null);
  isResendingVerification = signal(false);

  loginForm = this.fb.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required]],
  });

  get emailControl() {
    return this.loginForm.get('email');
  }

  onSubmit(): void {
    if (this.loginForm.invalid) {
      return;
    }

    this.isSubmitting.set(true);
    this.loginError.set(null);
    this.showResendVerification.set(false);
    this.resendVerificationMessage.set(null);
    const { email, password } = this.loginForm.getRawValue();

    if (email && password) {
      this.authService
        .login({ email, password })
        .pipe(finalize(() => this.isSubmitting.set(false)))
        .subscribe({
          next: () => this.router.navigate(['/dashboard']),
          error: (err: HttpErrorResponse) => {
            if (err.status === 403) {
              // Assuming 403 is for "Email Not Verified" as per BLA
              this.loginError.set(
                'Email not verified. Please check your email.'
              );
              this.showResendVerification.set(true);
            } else {
              this.loginError.set(
                'Invalid email or password. Please try again.'
              );
            }
          },
        });
    }
  }

  onResendVerificationEmail(): void {
    const email = this.emailControl?.value;
    if (!email || this.emailControl?.invalid) {
      this.resendVerificationMessage.set(
        'Please enter a valid email address.'
      );
      return;
    }

    this.isResendingVerification.set(true);
    this.resendVerificationMessage.set(null);
    this.loginError.set(null); // Clear previous login errors

    this.authService
      .resendVerification(email)
      .pipe(finalize(() => this.isResendingVerification.set(false)))
      .subscribe({
        next: () => {
          this.resendVerificationMessage.set(
            'A new verification email has been sent. Please check your inbox.'
          );
          this.showResendVerification.set(false); // Optionally hide the button after success
        },
        error: (err: HttpErrorResponse) => {
          // BLA 3.8.6: "Email address already verified." or "Email address not found in the system (handle with generic message...)"
          // For simplicity here, showing a generic error, but could be more specific based on backend response
          if (err.status === 409) { // Example: Conflict if already verified
             this.resendVerificationMessage.set('This email address has already been verified. You can try logging in.');
          } else {
             this.resendVerificationMessage.set(
              'Failed to resend verification email. Please try again later.'
            );
          }
        },
      });
  }
}
