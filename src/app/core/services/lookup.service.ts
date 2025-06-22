import { Injectable } from '@angular/core';
import { Observable, of } from 'rxjs';
import { delay } from 'rxjs/operators'; // For simulating network delay

export interface Country {
  id: string;
  name: string;
}

export interface CompanyType {
  id: string;
  name: string;
  description?: string;
}

export interface LocaleInfo { // Renamed from Locale to avoid conflict with global Locale type
  id: string;
  code: string; // e.g., 'en-US', 'bg-BG'
  name: string; // e.g., 'English (US)', 'Bulgarian (Bulgaria)'
}

export interface Currency {
  id: string;
  code: string; // e.g., 'USD', 'EUR', 'BGN'
  name: string; // e.g., 'US Dollar', 'Euro', 'Bulgarian Lev'
  symbol: string;
}

@Injectable({
  providedIn: 'root',
})
export class LookupService {
  constructor() {}

  // Mock data - replace with actual API calls later
  private mockCountries: Country[] = [
    { id: 'uuid-country-bg', name: 'Bulgaria' },
    { id: 'uuid-country-us', name: 'United States' },
    { id: 'uuid-country-de', name: 'Germany' },
    { id: 'uuid-country-gb', name: 'United Kingdom' },
  ];

  private mockCompanyTypes: CompanyType[] = [
    { id: 'uuid-ctype-ltd', name: 'Limited Liability Company (LTD/LLC)' },
    { id: 'uuid-ctype-sole', name: 'Sole Proprietorship' },
    { id: 'uuid-ctype-corp', name: 'Corporation' },
    { id: 'uuid-ctype-ngo', name: 'Non-Governmental Organization (NGO)' },
  ];

  private mockLocales: LocaleInfo[] = [
    { id: 'uuid-locale-enus', code: 'en-US', name: 'English (United States)' },
    { id: 'uuid-locale-bgbg', code: 'bg-BG', name: 'Bulgarian (Bulgaria)' },
    { id: 'uuid-locale-dede', code: 'de-DE', name: 'German (Germany)' },
  ];

  private mockCurrencies: Currency[] = [
    { id: 'uuid-curr-bgn', code: 'BGN', name: 'Bulgarian Lev', symbol: 'лв' },
    { id: 'uuid-curr-usd', code: 'USD', name: 'US Dollar', symbol: '$' },
    { id: 'uuid-curr-eur', code: 'EUR', name: 'Euro', symbol: '€' },
    { id: 'uuid-curr-gbp', code: 'GBP', name: 'British Pound', symbol: '£' },
  ];

  getCountries(): Observable<Country[]> {
    return of(this.mockCountries).pipe(delay(300)); // Simulate delay
  }

  getCompanyTypes(): Observable<CompanyType[]> {
    return of(this.mockCompanyTypes).pipe(delay(300));
  }

  getLocales(): Observable<LocaleInfo[]> {
    return of(this.mockLocales).pipe(delay(300));
  }

  getCurrencies(): Observable<Currency[]> {
    return of(this.mockCurrencies).pipe(delay(300));
  }
}
