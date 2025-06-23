import { TestBed } from '@angular/core/testing';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { CompanyService, CompanyCreationData } from './company.service';
import { environment } from '../../../environments/environment'; // Standardized path alias
import { describe, it, expect, beforeEach, afterEach } from 'vitest'; // Import Vitest globals
import { provideHttpClient } from '@angular/common/http';
import { provideZonelessChangeDetection } from '@angular/core';
import { lastValueFrom } from 'rxjs';

describe('CompanyService', () => {
  let service: CompanyService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        CompanyService,
        provideHttpClient(),
        provideHttpClientTesting(),
        provideZonelessChangeDetection(),
      ],
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
    const mockCompanyData: CompanyCreationData = {
      company_name: 'Test Co',
      company_eik: '123456789',
      company_country_id: 'country-uuid',
      company_type_id: 'type-uuid',
      company_default_locale_id: 'locale-uuid',
      company_default_currency_id: 'currency-uuid',
      company_address_line1: null,
      company_city: null,
    };

    it('should POST to the correct endpoint with company data', async () => {
      const mockResponse = { id: 'new-company-uuid', ...mockCompanyData };

      const requestPromise = lastValueFrom(
        service.createCompany(mockCompanyData)
      );

      const req = httpMock.expectOne(`${environment.apiUrl}/companies`);
      expect(req.request.method).toBe('POST');
      expect(req.request.body).toEqual(mockCompanyData);

      req.flush(mockResponse);

      const response = await requestPromise;
      expect(response).toEqual(mockResponse);
    });

    it('should handle HTTP errors', async () => {
      const errorMessage = 'Failed to create company';
      const requestPromise = lastValueFrom(
        service.createCompany(mockCompanyData)
      );

      const req = httpMock.expectOne(`${environment.apiUrl}/companies`);
      req.flush(errorMessage, { status: 400, statusText: 'Bad Request' });

      await expect(requestPromise).rejects.toThrow();
    });
  });
});
