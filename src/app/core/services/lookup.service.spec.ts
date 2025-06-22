import { TestBed } from '@angular/core/testing';
import { LookupService, Country, CompanyType, LocaleInfo, Currency } from './lookup.service';
import { of, lastValueFrom } from 'rxjs'; // Import lastValueFrom for async tests
import { delay } from 'rxjs/operators';
import { describe, it, expect, beforeEach } from 'vitest'; // Import Vitest globals

describe('LookupService', () => {
  let service: LookupService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [LookupService],
    });
    service = TestBed.inject(LookupService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  it('getCountries() should return an Observable of mock countries', async () => {
    const countries = await lastValueFrom(service.getCountries());
    expect(countries.length).toBeGreaterThan(0);
    expect(countries[0].id).toBeDefined();
    expect(countries[0].name).toBeDefined();
  });

  it('getCompanyTypes() should return an Observable of mock company types', async () => {
    const types = await lastValueFrom(service.getCompanyTypes());
    expect(types.length).toBeGreaterThan(0);
    expect(types[0].id).toBeDefined();
    expect(types[0].name).toBeDefined();
  });

  it('getLocales() should return an Observable of mock locales', async () => {
    const locales = await lastValueFrom(service.getLocales());
    expect(locales.length).toBeGreaterThan(0);
    expect(locales[0].id).toBeDefined();
    expect(locales[0].code).toBeDefined();
    expect(locales[0].name).toBeDefined();
  });

  it('getCurrencies() should return an Observable of mock currencies', async () => {
    const currencies = await lastValueFrom(service.getCurrencies());
    expect(currencies.length).toBeGreaterThan(0);
    expect(currencies[0].id).toBeDefined();
    expect(currencies[0].code).toBeDefined();
    expect(currencies[0].name).toBeDefined();
    expect(currencies[0].symbol).toBeDefined();
  });
});
