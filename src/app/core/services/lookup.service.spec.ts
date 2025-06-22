import { TestBed } from '@angular/core/testing';
import { LookupService, Country, CompanyType, LocaleInfo, Currency } from './lookup.service';
import { of } from 'rxjs';
import { delay } from 'rxjs/operators';

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

  it('getCountries() should return an Observable of mock countries', (done) => {
    service.getCountries().subscribe((countries: Country[]) => {
      expect(countries.length).toBeGreaterThan(0);
      expect(countries[0].id).toBeDefined();
      expect(countries[0].name).toBeDefined();
      done();
    });
  });

  it('getCompanyTypes() should return an Observable of mock company types', (done) => {
    service.getCompanyTypes().subscribe((types: CompanyType[]) => {
      expect(types.length).toBeGreaterThan(0);
      expect(types[0].id).toBeDefined();
      expect(types[0].name).toBeDefined();
      done();
    });
  });

  it('getLocales() should return an Observable of mock locales', (done) => {
    service.getLocales().subscribe((locales: LocaleInfo[]) => {
      expect(locales.length).toBeGreaterThan(0);
      expect(locales[0].id).toBeDefined();
      expect(locales[0].code).toBeDefined();
      expect(locales[0].name).toBeDefined();
      done();
    });
  });

  it('getCurrencies() should return an Observable of mock currencies', (done) => {
    service.getCurrencies().subscribe((currencies: Currency[]) => {
      expect(currencies.length).toBeGreaterThan(0);
      expect(currencies[0].id).toBeDefined();
      expect(currencies[0].code).toBeDefined();
      expect(currencies[0].name).toBeDefined();
      expect(currencies[0].symbol).toBeDefined();
      done();
    });
  });
});
