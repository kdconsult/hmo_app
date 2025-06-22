import { Component, OnInit, inject, signal, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, Validators, ReactiveFormsModule } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatSelectModule } from '@angular/material/select';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatIconModule } from '@angular/material/icon';


import { LookupService, Country, CompanyType, LocaleInfo, Currency } from '@/core/services/lookup.service';
import { CompanyService, CompanyCreationData } from '@/core/services/company.service';
import { AuthService } from '@/auth/auth.service'; // For updating token if needed

import { Observable, forkJoin } from 'rxjs';
import { finalize, tap } from 'rxjs/operators';

@Component({
  selector: 'app-create-company',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    RouterModule,
    MatCardModule,
    MatFormFieldModule,
    MatInputModule,
    MatButtonModule,
    MatSelectModule,
    MatProgressSpinnerModule,
    MatIconModule
  ],
  templateUrl: './create-company.component.html',
  styleUrls: ['./create-company.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class CreateCompanyComponent implements OnInit {
  private fb = inject(FormBuilder);
  private router = inject(Router);
  private lookupService = inject(LookupService);
  private companyService = inject(CompanyService);
  private authService = inject(AuthService); // To update token

  isLoadingLookups = signal(true);
  isSubmitting = signal(false);
  errorMessage = signal<string | null>(null);
  successMessage = signal<string | null>(null);

  countries$: Observable<Country[]> = this.lookupService.getCountries();
  companyTypes$: Observable<CompanyType[]> = this.lookupService.getCompanyTypes();
  locales$: Observable<LocaleInfo[]> = this.lookupService.getLocales();
  currencies$: Observable<Currency[]> = this.lookupService.getCurrencies();

  companyForm = this.fb.group({
    company_name: ['', [Validators.required, Validators.minLength(3), Validators.maxLength(100)]],
    company_eik: ['', [Validators.required, Validators.pattern(/^[0-9]{9,13}$/)]], // Basic EIK/VAT pattern
    company_country_id: ['', [Validators.required]],
    company_type_id: ['', [Validators.required]],
    company_default_locale_id: ['', [Validators.required]],
    company_default_currency_id: ['', [Validators.required]],
    company_address_line1: ['', [Validators.maxLength(255)]], // Optional
    company_city: ['', [Validators.maxLength(100)]], // Optional
  });

  ngOnInit(): void {
    // Load all lookups initially
    forkJoin({
      countries: this.countries$,
      companyTypes: this.companyTypes$,
      locales: this.locales$,
      currencies: this.currencies$,
    })
    .pipe(finalize(() => this.isLoadingLookups.set(false)))
    .subscribe({
      error: (err) => {
        console.error('Failed to load lookup data', err);
        this.errorMessage.set('Failed to load required data for the form. Please try refreshing the page.');
        this.companyForm.disable();
      }
    });
  }

  onSubmit(): void {
    if (this.companyForm.invalid) {
      this.companyForm.markAllAsTouched();
      return;
    }

    this.isSubmitting.set(true);
    this.errorMessage.set(null);
    this.successMessage.set(null);

    const formData = this.companyForm.getRawValue() as CompanyCreationData;

    this.companyService.createCompany(formData)
      .pipe(finalize(() => this.isSubmitting.set(false)))
      .subscribe({
        next: (response) => {
          // BLA 3.7.5: "Implement logic to update the stored JWT if the backend returns a new one with company context."
          // Backend might return new accessToken (definitely) and optionally a new refreshToken (if rotation is used for this event)
          if (response && response.accessToken) {
            // AuthService.updateTokens will handle using existing refresh token if new one isn't provided
            this.authService.updateTokens(response.accessToken, response.refreshToken);
          }
          // After token update, authService.currentCompanyId$ should emit the new company ID if present in the new token.
          // The AuthenticatedLayoutComponent will then NOT redirect back to create-company.

          this.successMessage.set(`Company '${formData.company_name}' created successfully! Redirecting to dashboard...`);
          this.companyForm.reset();
          this.companyForm.disable();
          setTimeout(() => this.router.navigate(['/dashboard']), 3000);
        },
        error: (err) => {
          console.error('Company creation failed', err);
          if (err.error && err.error.message) {
            this.errorMessage.set(`Error: ${err.error.message}`);
          } else if (err.status === 409) { // Example: EIK already exists
             this.errorMessage.set('Company creation failed: This EIK might already be registered.');
          }
          else {
            this.errorMessage.set('An unexpected error occurred during company creation. Please try again.');
          }
        }
      });
  }
}
