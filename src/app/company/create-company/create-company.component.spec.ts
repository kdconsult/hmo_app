import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { of, throwError, forkJoin } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { NoopAnimationsModule } from '@angular/platform-browser/animations';

import { CreateCompanyComponent } from './create-company.component';
import { LookupService, Country, CompanyType, LocaleInfo, Currency } from '@/core/services/lookup.service';
import { CompanyService, CompanyCreationData } from '@/core/services/company.service';
import { AuthService } from '@/auth/auth.service';

import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest'; // Import Vitest globals

// Material Modules
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatSelectModule } from '@angular/material/select';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatIconModule } from '@angular/material/icon';

class MockLookupService {
  getCountries = vi.fn().mockReturnValue(of([] as Country[]));
  getCompanyTypes = vi.fn().mockReturnValue(of([] as CompanyType[]));
  getLocales = vi.fn().mockReturnValue(of([] as LocaleInfo[]));
  getCurrencies = vi.fn().mockReturnValue(of([] as Currency[]));
}

class MockCompanyService {
  createCompany = vi.fn();
}

class MockAuthService {
  updateTokens = vi.fn();
  logout = vi.fn();
  getRefreshToken = vi.fn().mockReturnValue('fake-refresh-token');
}

class MockRouter {
  navigate = vi.fn();
}

describe('CreateCompanyComponent', () => {
  let component: CreateCompanyComponent;
  let fixture: ComponentFixture<CreateCompanyComponent>;
  let lookupService: MockLookupService;
  let companyService: MockCompanyService;
  let authService: MockAuthService;
  let router: MockRouter;

  const mockCountries: Country[] = [{ id: 'c1', name: 'Country1' }];
  const mockCompanyTypes: CompanyType[] = [{ id: 't1', name: 'Type1' }];
  const mockLocales: LocaleInfo[] = [{ id: 'l1', code: 'en', name: 'English' }];
  const mockCurrencies: Currency[] = [{ id: 'cur1', code: 'USD', name: 'Dollar', symbol: '$' }];


  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [
        CreateCompanyComponent, // Standalone
        ReactiveFormsModule,
        NoopAnimationsModule,
        MatCardModule, MatFormFieldModule, MatInputModule, MatButtonModule, MatSelectModule, MatProgressSpinnerModule, MatIconModule
      ],
      providers: [
        { provide: LookupService, useClass: MockLookupService },
        { provide: CompanyService, useClass: MockCompanyService },
        { provide: AuthService, useClass: MockAuthService },
        { provide: Router, useClass: MockRouter },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(CreateCompanyComponent);
    component = fixture.componentInstance;
    lookupService = TestBed.inject(LookupService) as unknown as MockLookupService;
    companyService = TestBed.inject(CompanyService) as unknown as MockCompanyService;
    authService = TestBed.inject(AuthService) as unknown as MockAuthService;
    router = TestBed.inject(Router) as unknown as MockRouter;

    // Setup default successful lookup mocks
    lookupService.getCountries.mockReturnValue(of(mockCountries));
    lookupService.getCompanyTypes.mockReturnValue(of(mockCompanyTypes));
    lookupService.getLocales.mockReturnValue(of(mockLocales));
    lookupService.getCurrencies.mockReturnValue(of(mockCurrencies));
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('should create', () => {
    fixture.detectChanges(); // ngOnInit
    expect(component).toBeTruthy();
  });

  describe('Lookup Data Loading', () => {
    it('should call lookup services on init and set isLoadingLookups correctly', fakeAsync(() => {
      expect(component.isLoadingLookups()).toBe(true); // before ngOnInit / detectChanges
      fixture.detectChanges(); // ngOnInit
      expect(lookupService.getCountries).toHaveBeenCalled();
      expect(lookupService.getCompanyTypes).toHaveBeenCalled();
      expect(lookupService.getLocales).toHaveBeenCalled();
      expect(lookupService.getCurrencies).toHaveBeenCalled();

      tick(); // for forkJoin and finalize
      expect(component.isLoadingLookups()).toBe(false);
    }));

    it('should display error and disable form if lookup data fails to load', fakeAsync(() => {
      lookupService.getCountries.mockReturnValue(throwError(() => new Error('Failed to load countries')));
      fixture.detectChanges(); // ngOnInit
      tick();

      expect(component.isLoadingLookups()).toBe(false);
      expect(component.errorMessage()).toBe('Failed to load required data for the form. Please try refreshing the page.');
      expect(component.companyForm.disabled).toBe(true);
    }));
  });

  describe('Form Validation', () => {
    beforeEach(() => {
        fixture.detectChanges(); // Load lookups
        tick(); // ensure lookups are loaded
    });

    it('should invalidate form with empty required fields', () => {
      component.companyForm.reset(); // Clear all fields
      expect(component.companyForm.valid).toBe(false);
      expect(component.companyForm.controls['company_name'].hasError('required')).toBe(true);
      // ... test other required fields similarly
    });

    it('should validate company_eik pattern', () => {
      component.companyForm.controls['company_eik'].setValue('invalid-eik');
      expect(component.companyForm.controls['company_eik'].hasError('pattern')).toBe(true);
      component.companyForm.controls['company_eik'].setValue('123456789'); // Valid
      expect(component.companyForm.controls['company_eik'].hasError('pattern')).toBe(false);
    });

    it('should be valid with all required fields filled correctly', () => {
      component.companyForm.setValue({
        company_name: 'Test Corp',
        company_eik: '1234567890',
        company_country_id: 'c1',
        company_type_id: 't1',
        company_default_locale_id: 'l1',
        company_default_currency_id: 'cur1',
        company_address_line1: '', // Optional
        company_city: '' // Optional
      });
      expect(component.companyForm.valid).toBe(true);
    });
  });

  describe('Company Creation Submission', () => {
    const validCompanyData: CompanyCreationData = {
      company_name: 'Test Corp',
      company_eik: '1234567890',
      company_country_id: 'c1',
      company_type_id: 't1',
      company_default_locale_id: 'l1',
      company_default_currency_id: 'cur1',
      company_address_line1: '123 Main St',
      company_city: 'Testville'
    };

    beforeEach(fakeAsync(() => {
      fixture.detectChanges(); // ngOnInit to load lookups
      tick();
      component.companyForm.setValue(validCompanyData);
    }));

    it('should call companyService.createCompany and authService.updateTokens on success, then navigate', fakeAsync(() => {
      const mockResponse = {
        message: 'Company created',
        accessToken: 'new-access-token',
        refreshToken: 'new-refresh-token'
      };
      companyService.createCompany.mockReturnValue(of(mockResponse));

      component.onSubmit();
      tick();

      expect(companyService.createCompany).toHaveBeenCalledWith(validCompanyData);
      expect(authService.updateTokens).toHaveBeenCalledWith(mockResponse.accessToken, mockResponse.refreshToken);
      expect(component.successMessage()).toContain('created successfully');
      expect(component.companyForm.disabled).toBe(true);

      tick(3000); // For setTimeout navigation
      expect(router.navigate).toHaveBeenCalledWith(['/dashboard']);
    }));

    it('should call updateTokens with only new access token if refresh token is not in response', fakeAsync(() => {
        const mockResponse = { message: 'Company created', accessToken: 'new-access-token-only' };
        companyService.createCompany.mockReturnValue(of(mockResponse));
        // authService.getRefreshToken is already mocked to return 'fake-refresh-token'

        component.onSubmit();
        tick();

        expect(authService.updateTokens).toHaveBeenCalledWith(mockResponse.accessToken, undefined); // No new refresh token in response
        // The service's updateTokens method should then use the existing one.
    }));


    it('should display error message on company creation failure (e.g., 409 EIK exists)', fakeAsync(() => {
      const errorResponse = new HttpErrorResponse({ status: 409, error: { message: 'EIK exists' } });
      companyService.createCompany.mockReturnValue(throwError(() => errorResponse));
      component.onSubmit();
      tick();

      expect(companyService.createCompany).toHaveBeenCalledWith(validCompanyData);
      expect(authService.updateTokens).not.toHaveBeenCalled();
      expect(component.errorMessage()).toBe('Company creation failed: This EIK might already be registered.');
      expect(router.navigate).not.toHaveBeenCalled();
    }));

    it('should display error message from error.error.message if available', fakeAsync(() => {
      const specificErrorMessage = "A very specific error occurred.";
      const errorResponse = new HttpErrorResponse({ status: 500, error: { message: specificErrorMessage } });
      companyService.createCompany.mockReturnValue(throwError(() => errorResponse));
      component.onSubmit();
      tick();
      expect(component.errorMessage()).toBe(`Error: ${specificErrorMessage}`);
    }));


    it('should set isSubmitting correctly during submission', fakeAsync(() => {
      companyService.createCompany.mockReturnValue(of({ accessToken: 'token' }));
      expect(component.isSubmitting()).toBe(false);
      component.onSubmit();
      expect(component.isSubmitting()).toBe(true);
      tick();
      expect(component.isSubmitting()).toBe(false);
    }));

    it('should not submit if form is invalid and mark form as touched', () => {
      component.companyForm.controls['company_name'].setValue(''); // Make form invalid
      const markSpy = vi.spyOn(component.companyForm, 'markAllAsTouched');
      component.onSubmit();
      expect(companyService.createCompany).not.toHaveBeenCalled();
      expect(markSpy).toHaveBeenCalled();
    });
  });
});
