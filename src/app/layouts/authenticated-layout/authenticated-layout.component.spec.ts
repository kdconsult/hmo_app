import { ComponentFixture, TestBed } from '@angular/core/testing';
import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest';
import { Router, NavigationEnd, Event, provideRouter } from '@angular/router';
import { AuthenticatedLayoutComponent } from './authenticated-layout.component';
import { AuthService } from '../../auth/auth.service';
import { BreakpointObserver } from '@angular/cdk/layout';
import { of, Subject } from 'rxjs';
import { provideZonelessChangeDetection } from '@angular/core';
import { Component } from '@angular/core';

@Component({ standalone: true, template: '' })
class DummyComponent {}

class MockAuthService {
  logout = vi.fn();
  isLoggedIn$ = new Subject<boolean>();
  currentCompanyId$ = new Subject<string | null>();
}

class MockBreakpointObserver {
  observe = vi.fn().mockReturnValue(of({ matches: false, breakpoints: {} }));
}

class MockRouter {
  public events = new Subject<Event>();
  // The only method we need to spy on for our test is navigate
  navigate = vi.fn().mockResolvedValue(true);

  // Method to manually trigger navigation events for testing
  triggerNavEnd(url: string, urlAfterRedirects: string) {
    this.events.next(new NavigationEnd(1, url, urlAfterRedirects));
  }
}

describe('AuthenticatedLayoutComponent', () => {
  let component: AuthenticatedLayoutComponent;
  let fixture: ComponentFixture<AuthenticatedLayoutComponent>;
  let authService: MockAuthService;
  let router: MockRouter;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [AuthenticatedLayoutComponent],
      providers: [
        provideZonelessChangeDetection(),
        provideRouter([
          // Define dummy routes used in tests
          { path: 'create-company', component: DummyComponent },
          { path: 'dashboard', component: DummyComponent },
        ]),
        { provide: AuthService, useClass: MockAuthService },
        { provide: BreakpointObserver, useClass: MockBreakpointObserver },
        // We override the Router provider from provideRouter to use our mock with spies
        { provide: Router, useClass: MockRouter },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(AuthenticatedLayoutComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService) as unknown as MockAuthService;
    router = TestBed.inject(Router) as unknown as MockRouter;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('should create', () => {
    fixture.detectChanges();
    expect(component).toBeTruthy();
  });

  it('should call authService.logout when logout() is called', () => {
    fixture.detectChanges();
    component.logout();
    expect(authService.logout).toHaveBeenCalled();
  });

  describe('Redirection Logic', () => {
    it('should navigate to /create-company if logged in, no companyId, and not on /create-company', async () => {
      fixture.detectChanges(); // ngOnInit subscribes

      authService.isLoggedIn$.next(true);
      authService.currentCompanyId$.next(null);
      router.triggerNavEnd('/dashboard', '/dashboard');

      await fixture.whenStable();
      fixture.detectChanges();

      expect(router.navigate).toHaveBeenCalledWith(['/create-company']);
    });

    it('should NOT navigate if not logged in', async () => {
      fixture.detectChanges();

      authService.isLoggedIn$.next(false);
      authService.currentCompanyId$.next(null);
      router.triggerNavEnd('/dashboard', '/dashboard');

      await fixture.whenStable();
      fixture.detectChanges();

      expect(router.navigate).not.toHaveBeenCalled();
    });

    it('should NOT navigate if companyId exists', async () => {
      fixture.detectChanges();

      authService.isLoggedIn$.next(true);
      authService.currentCompanyId$.next('company123');
      router.triggerNavEnd('/dashboard', '/dashboard');

      await fixture.whenStable();
      fixture.detectChanges();

      expect(router.navigate).not.toHaveBeenCalled();
    });

    it('should NOT navigate if already on /create-company', async () => {
      fixture.detectChanges();

      authService.isLoggedIn$.next(true);
      authService.currentCompanyId$.next(null);
      router.triggerNavEnd('/create-company', '/create-company');

      await fixture.whenStable();
      fixture.detectChanges();

      expect(router.navigate).not.toHaveBeenCalled();
    });
  });
});
