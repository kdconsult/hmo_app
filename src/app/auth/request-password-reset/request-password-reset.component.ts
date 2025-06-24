import {
  Component,
  inject,
  signal,
  ChangeDetectionStrategy,
} from '@angular/core';
import { FormBuilder, Validators, ReactiveFormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router'; // RouterModule for routerLink
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatIconModule } from '@angular/material/icon';

import { AuthService } from '@/auth/auth.service';
import { finalize } from 'rxjs/operators';

@Component({
  selector: 'app-request-password-reset',
  imports: [
    ReactiveFormsModule,
    RouterModule,
    MatCardModule,
    MatFormFieldModule,
    MatInputModule,
    MatButtonModule,
    MatProgressSpinnerModule,
    MatIconModule,
  ],
  templateUrl: './request-password-reset.component.html',
  styleUrls: ['./request-password-reset.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class RequestPasswordResetComponent {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);

  isLoading = signal(false);
  message = signal<string | null>(null);
  messageType = signal<'success' | 'error'>('success'); // To style message

  requestResetForm = this.fb.group({
    email: ['', [Validators.required, Validators.email]],
  });

  get emailControl() {
    return this.requestResetForm.get('email');
  }

  onSubmit(): void {
    if (this.requestResetForm.invalid) {
      this.requestResetForm.markAllAsTouched();
      return;
    }

    const email = this.emailControl?.value;

    if (!email) {
      this.messageType.set('error');
      this.message.set('Please enter a valid email address.');
      return;
    }

    this.isLoading.set(true);
    this.message.set(null);

    this.authService
      .requestPasswordReset(email)
      .pipe(finalize(() => this.isLoading.set(false)))
      .subscribe({
        next: () => {
          // BLA 3.6.1.4.6: Always Return Generic Success Response
          this.messageType.set('success');
          this.message.set(
            `If an account exists for ${email}, a password reset link has been sent. Please check your email.`
          );
          this.requestResetForm.reset();
        },
        error: (err) => {
          // Even on error, show generic success message to prevent email enumeration.
          // Log the actual error for debugging if necessary.
          console.error('Request password reset error:', err);
          this.messageType.set('success'); // Still show success as per BLA
          this.message.set(
            `If an account exists for ${email}, a password reset link has been sent. Please check your email.`
          );
          this.requestResetForm.reset();
        },
      });
  }
}
