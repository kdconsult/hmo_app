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
import { Router, RouterModule } from '@angular/router';
import { CommonModule } from '@angular/common';
import { finalize } from 'rxjs';

import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatCheckboxModule } from '@angular/material/checkbox';

import { AuthService } from '../auth.service';

// Custom Validator
function passwordsMatchValidator(
  control: AbstractControl
): ValidationErrors | null {
  const password = control.get('password')?.value;
  const confirmPassword = control.get('confirmPassword')?.value;
  return password === confirmPassword ? null : { passwordsMismatch: true };
}

@Component({
  selector: 'app-register',
  imports: [
    CommonModule,
    RouterModule,
    ReactiveFormsModule,
    MatCardModule,
    MatFormFieldModule,
    MatInputModule,
    MatButtonModule,
    MatIconModule,
    MatCheckboxModule,
  ],
  templateUrl: './register.component.html',
  styleUrl: './register.component.scss',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class RegisterComponent {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);

  hidePassword = signal(true);
  registrationError = signal<string | null>(null);
  isSubmitting = signal(false);

  registerForm = this.fb.group(
    {
      first_name: ['', [Validators.required]],
      last_name: ['', [Validators.required]],
      email: ['', [Validators.required, Validators.email]],
      password: ['', [Validators.required, Validators.minLength(6)]],
      confirmPassword: ['', [Validators.required]],
      terms_agreed: [false, [Validators.requiredTrue]],
    },
    { validators: passwordsMatchValidator }
  );

  onSubmit(): void {
    if (this.registerForm.invalid) {
      return;
    }

    this.isSubmitting.set(true);
    this.registrationError.set(null);

    // We can omit confirmPassword from the value sent to the backend
    const { first_name, last_name, email, password, terms_agreed } =
      this.registerForm.getRawValue();

    if (first_name && last_name && email && password && terms_agreed) {
      this.authService
        .register({ first_name, last_name, email, password, terms_agreed })
        .pipe(finalize(() => this.isSubmitting.set(false)))
        .subscribe({
          next: () => this.router.navigate(['/dashboard']),
          error: (err) => {
            // A more specific error could be returned from the API
            this.registrationError.set(
              'Registration failed. The email might already be in use.'
            );
          },
        });
    }
  }
}
