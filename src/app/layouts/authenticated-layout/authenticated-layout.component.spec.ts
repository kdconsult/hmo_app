import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { RouterTestingModule } from '@angular/router/testing';
import { NoopAnimationsModule } from '@angular/platform-browser/animations';
import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest';
import { Router, NavigationEnd, Event } from '@angular/router'; // Import NavigationEnd and Event

import { AuthenticatedLayoutComponent } from './authenticated-layout.component';
import { AuthService } from '@/auth/auth.service';
import { BreakpointObserver } from '@angular/cdk/layout';
import { of, Subject } from 'rxjs';

// Mock AuthService
class MockAuthService {
  logout = vi.fn();
  isLoggedIn$ = new Subject<boolean>();
  currentCompanyId$ = new Subject<string | null>();
}

// Mock BreakpointObserver
class MockBreakpointObserver {
  observe = vi.fn().mockReturnValue(of({ matches: false, breakpoints: {} }));
}

// Mock Router - use a Subject for events
class MockRouter {
    navigate = vi.fn().mockResolvedValue(true);
    events = new Subject<Event>(); // Use Subject for events
    // Add a dummy url property or getter if component tries to access it, though not in current component logic
    get url(): string { return this._currentUrl; }
    private _currentUrl: string = '/';
    // Simulate navigation for testing purposes, though not strictly needed for this component's current logic
    public triggerNavEnd(url: string, urlAfterRedirects: string) {
        this._currentUrl = urlAfterRedirects;
        (this.events as Subject<Event>).next(new NavigationEnd(1, url, urlAfterRedirects));
    }
}


describe('AuthenticatedLayoutComponent', () => {
  let component: AuthenticatedLayoutComponent;
  let fixture: ComponentFixture<AuthenticatedLayoutComponent>;
  let authService: MockAuthService;
  let breakpointObserver: MockBreakpointObserver;
  let router: MockRouter;


  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [
        AuthenticatedLayoutComponent,
        NoopAnimationsModule,
      ],
      providers: [
        { provide: AuthService, useClass: MockAuthService },
        { provide: BreakpointObserver, useClass: MockBreakpointObserver },
        { provide: Router, useClass: MockRouter },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(AuthenticatedLayoutComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService) as unknown as MockAuthService;
    breakpointObserver = TestBed.inject(BreakpointObserver) as unknown as MockBreakpointObserver;
    router = TestBed.inject(Router) as unknown as MockRouter;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('should create', () => {
    fixture.detectChanges(); // Trigger ngOnInit
    expect(component).toBeTruthy();
  });

  it('should call authService.logout when logout() is called', () => {
    fixture.detectChanges();
    component.logout();
    expect(authService.logout).toHaveBeenCalled();
  });

  describe('Redirection Logic', () => {
    it('should navigate to /create-company if logged in, no companyId, and not on /create-company', fakeAsync(() => {
      fixture.detectChanges(); // ngOnInit subscribes

      authService.isLoggedIn$.next(true);
      authService.currentCompanyId$.next(null);
      router.triggerNavEnd('/dashboard', '/dashboard'); // Simulate navigation
      tick(); // Allow time for combineLatest and async operations

      expect(router.navigate).toHaveBeenCalledWith(['/create-company']);
    }));

    it('should NOT navigate if not logged in', fakeAsync(() => {
      fixture.detectChanges();

      authService.isLoggedIn$.next(false);
      authService.currentCompanyId$.next(null);
      router.triggerNavEnd('/dashboard', '/dashboard');
      tick();

      expect(router.navigate).not.toHaveBeenCalledWith(['/create-company']);
    }));

    it('should NOT navigate if companyId exists', fakeAsync(() => {
      fixture.detectChanges();

      authService.isLoggedIn$.next(true);
      authService.currentCompanyId$.next('company123');
      router.triggerNavEnd('/dashboard', '/dashboard');
      tick();

      expect(router.navigate).not.toHaveBeenCalledWith(['/create-company']);
    }));

    it('should NOT navigate if already on /create-company', fakeAsync(() => {
      fixture.detectChanges();

      authService.isLoggedIn$.next(true);
      authService.currentCompanyId$.next(null);
      router.triggerNavEnd('/create-company', '/create-company');
      tick();

      expect(router.navigate).not.toHaveBeenCalledWith(['/create-company']);
    }));
  });
});
