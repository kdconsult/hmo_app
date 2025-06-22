import { TestBed } from '@angular/core/testing';
import {
  HttpClientTestingModule,
  HttpTestingController,
} from '@angular/common/http/testing';
import { CompanyService, CompanyCreationData } from './company.service';
import { environment } from '@/environments/environment'; // Standardized path alias
import { describe, it, expect, beforeEach, afterEach } from 'vitest'; // Import Vitest globals


describe('CompanyService', () => {
  let service: CompanyService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [HttpClientTestingModule],
      providers: [CompanyService],
    });
    service = TestBed.inject(CompanyService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    httpMock.verify(); // Make sure that there are no outstanding requests
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  describe('createCompany', () => {
    it('should make a POST request to the correct endpoint with company data', () => {
      const mockCompanyData: CompanyCreationData = {
        company_name: 'Test Co',
        company_eik: '123456789',
        company_country_id: 'country-uuid',
        company_type_id: 'type-uuid',
        company_default_locale_id: 'locale-uuid',
        company_default_currency_id: 'currency-uuid',
      };
      const mockResponse = { id: 'new-company-uuid', ...mockCompanyData };

      service.createCompany(mockCompanyData).subscribe(response => {
        expect(response).toEqual(mockResponse);
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/companies`);
      expect(req.request.method).toBe('POST');
      expect(req.request.body).toEqual(mockCompanyData);

      // The AuthInterceptor should add the Authorization header.
      // We don't test the interceptor's work here, but assume it does its job.
      // If we wanted to test that the service call triggers the interceptor,
      // it would require a more complex setup, usually done at interceptor test level.

      req.flush(mockResponse);
    });

    it('should handle HTTP errors', () => {
        const mockCompanyData: CompanyCreationData = {company_name: "Fail Co"} as CompanyCreationData; // minimal valid data
        const errorMessage = 'Failed to create company';

        const promise = new Promise<void>((resolve, reject) => {
            service.createCompany(mockCompanyData).subscribe({
                next: () => reject(new Error('should have failed with the 400 error')), // Use reject for Promise
                error: (error) => {
                    try {
                        expect(error.status).toBe(400);
                        expect(error.error).toBe(errorMessage);
                        resolve(); // Resolve on successful assertion
                    } catch (e) {
                        reject(e); // Reject if assertions fail
                    }
                }
            });
        });

        const req = httpMock.expectOne(`${environment.apiUrl}/companies`);
        req.flush(errorMessage, { status: 400, statusText: 'Bad Request' });
        return promise; // Return the promise for Vitest to await
    });
  });
});
