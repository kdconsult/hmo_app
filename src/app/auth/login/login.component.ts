import {
  Component,
  ChangeDetectionStrategy,
  inject,
  signal,
} from '@angular/core';
import { FormBuilder, Validators, ReactiveFormsModule } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { CommonModule } from '@angular/common';

import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';

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

  loginForm = this.fb.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required]],
  });

  onSubmit(): void {
    if (this.loginForm.invalid) {
      return;
    }

    this.isSubmitting.set(true);
    this.loginError.set(null);
    const { email, password } = this.loginForm.getRawValue();

    if (email && password) {
      this.authService
        .login({ email, password })
        .pipe(finalize(() => this.isSubmitting.set(false)))
        .subscribe({
          next: () => this.router.navigate(['/dashboard']),
          error: (err) =>
            this.loginError.set('Invalid email or password. Please try again.'),
        });
    }
  }
}
