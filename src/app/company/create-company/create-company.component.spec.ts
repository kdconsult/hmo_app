import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { of, throwError } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { provideNoopAnimations } from '@angular/platform-browser/animations';
import { provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { vi, describe, it, expect, beforeEach, afterEach, Mock } from 'vitest';

import { CreateCompanyComponent } from './create-company.component';
import {
  LookupService,
  Country,
  CompanyType,
  LocaleInfo,
  Currency,
} from '../../core/services/lookup.service';
import {
  CompanyService,
  CompanyCreationData,
} from '../../core/services/company.service';
import { AuthService } from '../../auth/auth.service';

// Preserving original Material Module imports
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatSelectModule } from '@angular/material/select';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatIconModule } from '@angular/material/icon';

describe('CreateCompanyComponent', () => {
  let component: CreateCompanyComponent;
  let fixture: ComponentFixture<CreateCompanyComponent>;
  let lookupService: LookupService;
  let companyService: CompanyService;
  let authService: AuthService;
  let router: Router;

  const mockCountries: Country[] = [{ id: 'c1', name: 'Country1' }];
  const mockCompanyTypes: CompanyType[] = [{ id: 't1', name: 'Type1' }];
  const mockLocales: LocaleInfo[] = [{ id: 'l1', code: 'en', name: 'English' }];
  const mockCurrencies: Currency[] = [
    { id: 'cur1', code: 'USD', name: 'Dollar', symbol: '$' },
  ];

  const setupTestBed = async (lookupError: boolean = false) => {
    await TestBed.configureTestingModule({
      imports: [
        CreateCompanyComponent,
        ReactiveFormsModule,
        MatCardModule,
        MatFormFieldModule,
        MatInputModule,
        MatButtonModule,
        MatSelectModule,
        MatProgressSpinnerModule,
        MatIconModule,
      ],
      providers: [
        provideZonelessChangeDetection(),
        provideRouter([{ path: 'dashboard', component: class {} }]),
        provideNoopAnimations(),
        {
          provide: LookupService,
          useValue: {
            getCountries: vi
              .fn()
              .mockReturnValue(
                lookupError
                  ? throwError(() => new Error('Lookup Failed'))
                  : of(mockCountries)
              ),
            getCompanyTypes: vi.fn().mockReturnValue(of(mockCompanyTypes)),
            getLocales: vi.fn().mockReturnValue(of(mockLocales)),
            getCurrencies: vi.fn().mockReturnValue(of(mockCurrencies)),
          },
        },
        {
          provide: CompanyService,
          useValue: { createCompany: vi.fn() },
        },
        {
          provide: AuthService,
          useValue: { updateTokens: vi.fn() },
        },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(CreateCompanyComponent);
    component = fixture.componentInstance;
    lookupService = TestBed.inject(LookupService);
    companyService = TestBed.inject(CompanyService);
    authService = TestBed.inject(AuthService);
    router = TestBed.inject(Router);
    vi.spyOn(router, 'navigate');
  };

  afterEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  it('should create', async () => {
    await setupTestBed();
    fixture.detectChanges();
    expect(component).toBeTruthy();
  });

  describe('Lookup Data Loading', () => {
    it('should call services and set loading signal', async () => {
      await setupTestBed();
      expect(component.isLoadingLookups()).toBe(true);
      fixture.detectChanges(); // ngOnInit
      await fixture.whenStable();

      expect(lookupService.getCountries).toHaveBeenCalled();
      expect(lookupService.getCompanyTypes).toHaveBeenCalled();
      expect(lookupService.getLocales).toHaveBeenCalled();
      expect(lookupService.getCurrencies).toHaveBeenCalled();
      expect(component.isLoadingLookups()).toBe(false);
    });

    it('should show error if lookup fails', async () => {
      await setupTestBed(true); // Configure with an error
      fixture.detectChanges(); // ngOnInit
      await fixture.whenStable();

      expect(component.isLoadingLookups()).toBe(false);
      expect(component.errorMessage()).toContain(
        'Failed to load required data'
      );
      expect(component.companyForm.disabled).toBe(true);
    });
  });

  describe('Form Validation and Submission', () => {
    const validCompanyData: CompanyCreationData = {
      company_name: 'Test Corp',
      company_eik: '1234567890',
      company_country_id: 'c1',
      company_type_id: 't1',
      company_default_locale_id: 'l1',
      company_default_currency_id: 'cur1',
      company_address_line1: '123 Main St',
      company_city: 'Testville',
    };

    beforeEach(async () => {
      await setupTestBed();
      fixture.detectChanges(); // Load lookups
      await fixture.whenStable();
      component.companyForm.setValue(validCompanyData);
    });

    it('should be valid when all required fields are filled', () => {
      expect(component.companyForm.valid).toBe(true);
    });

    it('should create company, update tokens, and navigate on success', async () => {
      vi.useFakeTimers();
      const mockResponse = {
        accessToken: 'new-access',
        refreshToken: 'new-refresh',
      };
      (companyService.createCompany as Mock).mockReturnValue(of(mockResponse));

      component.onSubmit();
      await fixture.whenStable();

      expect(companyService.createCompany).toHaveBeenCalledWith(
        validCompanyData
      );
      expect(authService.updateTokens).toHaveBeenCalledWith(
        'new-access',
        'new-refresh'
      );
      expect(component.successMessage()).toContain('created successfully');

      vi.advanceTimersByTime(3000);
      await fixture.whenStable();

      expect(router.navigate).toHaveBeenCalledWith(['/dashboard']);
    });

    it('should handle token update when refresh token is missing from response', async () => {
      const mockResponse = { accessToken: 'new-access-only' };
      (companyService.createCompany as Mock).mockReturnValue(of(mockResponse));

      component.onSubmit();
      await fixture.whenStable();

      expect(authService.updateTokens).toHaveBeenCalledWith(
        'new-access-only',
        undefined
      );
    });

    it('should show error message on 409 conflict', async () => {
      const error = new HttpErrorResponse({
        status: 409,
        error: { message: 'EIK exists' },
      });
      (companyService.createCompany as Mock).mockReturnValue(
        throwError(() => error)
      );
      component.onSubmit();
      await fixture.whenStable();
      expect(component.errorMessage()).toBe(
        'Company creation failed: This EIK might already be registered.'
      );
    });

    it('should show generic error for other API failures', async () => {
      const error = new HttpErrorResponse({ status: 500 });
      (companyService.createCompany as Mock).mockReturnValue(
        throwError(() => error)
      );
      component.onSubmit();
      await fixture.whenStable();
      expect(component.errorMessage()).toBe(
        'An unexpected error occurred during company creation. Please try again.'
      );
    });
  });
});
