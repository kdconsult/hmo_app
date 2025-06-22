import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '@/environments/environment';

// Define an interface for the company creation payload based on BLA 3.7.2
export interface CompanyCreationData {
  company_name: string;
  company_eik: string;
  company_country_id: string;
  company_type_id: string;
  company_default_locale_id: string;
  company_default_currency_id: string;
  // Optional fields from BLA 3.7.2
  company_address_line1?: string;
  company_city?: string;
  // company_post_code?: string; // Not explicitly in 3.7.2 but typical for address
  // company_region_name?: string; // Not explicitly in 3.7.2 but typical for address
}

@Injectable({
  providedIn: 'root',
})
export class CompanyService {
  private http = inject(HttpClient);
  private apiUrl = environment.apiUrl;

  constructor() {}

  createCompany(companyData: CompanyCreationData): Observable<any> {
    // The actual endpoint might be /companies, /company, /onboarding/company etc.
    // Using '/companies' as a placeholder.
    // This request will be intercepted by AuthInterceptor to add the Authorization header.
    return this.http.post<any>(`${this.apiUrl}/companies`, companyData);
  }
}
