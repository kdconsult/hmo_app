import { Component, OnInit, inject, signal, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon'; // For error/success icons

import { AuthService } from '../auth.service';
import { switchMap, catchError, tap } from 'rxjs/operators';
import { of } from 'rxjs';

@Component({
  selector: 'app-verify-email-status',
  standalone: true,
  imports: [
    CommonModule,
    RouterModule,
    MatProgressSpinnerModule,
    MatCardModule,
    MatButtonModule,
    MatIconModule
  ],
  templateUrl: './verify-email-status.component.html',
  styleUrls: ['./verify-email-status.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class VerifyEmailStatusComponent implements OnInit {
  private route = inject(ActivatedRoute);
  private authService = inject(AuthService);
  private router = inject(Router);

  isLoading = signal(true);
  verificationStatus = signal<'success' | 'error' | 'pending'>('pending');
  message = signal<string | null>(null);

  ngOnInit(): void {
    this.route.queryParamMap.pipe(
      switchMap(params => {
        const token = params.get('token');
        if (!token) {
          this.isLoading.set(false);
          this.verificationStatus.set('error');
          this.message.set('Verification token not found in URL.');
          return of(null); // End the stream
        }
        // Ensure authService.verifyEmailToken exists and returns an Observable
        return this.authService.verifyEmailToken(token).pipe(
          tap(() => {
            this.isLoading.set(false);
            this.verificationStatus.set('success');
            this.message.set('Email successfully verified! You can now log in.');
          }),
          catchError(error => {
            this.isLoading.set(false);
            this.verificationStatus.set('error');
            let errorMessage = 'Failed to verify email.';
            if (error.error && typeof error.error.message === 'string') {
              errorMessage = error.error.message;
            } else if (typeof error.message === 'string') {
              errorMessage = error.message;
            } else if (error.status === 400) {
                errorMessage = 'Invalid or expired verification link. Please try registering again or request a new verification email.';
            } else if (error.status === 404) {
                 errorMessage = 'Verification token not found or already used.';
            } else if (error.status === 409) {
                errorMessage = 'This email is already verified.';
            }
            this.message.set(errorMessage);
            return of(null); // Complete the observable chain
          })
        );
      })
    ).subscribe();
  }

  navigateToLogin(): void {
    this.router.navigate(['/login']);
  }
}
