import { TestBed } from '@angular/core/testing';
import {
  HttpClientTestingModule,
  HttpTestingController,
} from '@angular/common/http/testing';
import { CompanyService, CompanyCreationData } from './company.service';
import { environment } from '@/environments/environment';

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
        const mockCompanyData: CompanyCreationData = { /* ... */ } as CompanyCreationData;
        const errorMessage = 'Failed to create company';

        service.createCompany(mockCompanyData).subscribe({
            next: () => fail('should have failed with the 400 error'),
            error: (error) => {
                expect(error.status).toBe(400);
                expect(error.error).toBe(errorMessage);
            }
        });

        const req = httpMock.expectOne(`${environment.apiUrl}/companies`);
        req.flush(errorMessage, { status: 400, statusText: 'Bad Request' });
    });
  });
});
