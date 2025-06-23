import { ComponentFixture, TestBed } from '@angular/core/testing';
import { vi, describe, it, expect, beforeEach, afterEach } from 'vitest';
import { Router, NavigationEnd, Event, provideRouter } from '@angular/router';
import { provideNoopAnimations } from '@angular/platform-browser/animations';
import { AuthenticatedLayoutComponent } from './authenticated-layout.component';
import { AuthService } from '../../auth/auth.service';
import { BreakpointObserver, BreakpointState } from '@angular/cdk/layout';
import { of, Subject } from 'rxjs';
import { provideZonelessChangeDetection } from '@angular/core';
import { Component } from '@angular/core';
import { Mock } from 'vitest';

@Component({ standalone: true, template: '' })
class DummyComponent {}

describe('AuthenticatedLayoutComponent', () => {
  let component: AuthenticatedLayoutComponent;
  let fixture: ComponentFixture<AuthenticatedLayoutComponent>;
  let authService: AuthService; // Use actual type
  let router: Router; // Use actual type
  let breakpointObserver: BreakpointObserver; // Use actual type

  let mockIsLoggedIn$: Subject<boolean>;
  let mockCurrentCompanyId$: Subject<string | null>;
  let mockBreakpointState$: Subject<BreakpointState>;
  let routerEvents$: Subject<Event>;

  beforeEach(async () => {
    mockIsLoggedIn$ = new Subject<boolean>();
    mockCurrentCompanyId$ = new Subject<string | null>();
    mockBreakpointState$ = new Subject<BreakpointState>();
    routerEvents$ = new Subject<Event>();

    await TestBed.configureTestingModule({
      imports: [AuthenticatedLayoutComponent],
      providers: [
        provideZonelessChangeDetection(),
        provideNoopAnimations(),
        provideRouter([
          { path: 'create-company', component: DummyComponent },
          { path: 'dashboard', component: DummyComponent },
        ]),
        {
          provide: AuthService,
          useValue: {
            logout: vi.fn(),
            isLoggedIn$: mockIsLoggedIn$.asObservable(),
            currentCompanyId$: mockCurrentCompanyId$.asObservable(),
          },
        },
        {
          provide: BreakpointObserver,
          useValue: {
            observe: vi.fn().mockReturnValue(mockBreakpointState$.asObservable()),
          },
        },
        {
          provide: Router,
          useValue: {
            events: routerEvents$.asObservable(),
            navigate: vi.fn().mockResolvedValue(true),
          },
        },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(AuthenticatedLayoutComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService);
    router = TestBed.inject(Router); // router will be our mock object
    breakpointObserver = TestBed.inject(BreakpointObserver);
    // No need to spy on router.navigate here as it's already a vi.fn() from the mock
    // No need to cast router.events as it's controlled by routerEvents$
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

      mockIsLoggedIn$.next(true);
      mockCurrentCompanyId$.next(null);
      // Simulate BreakpointObserver emitting; actual value doesn't matter for this test's logic
      mockBreakpointState$.next({ matches: false, breakpoints: {} } as BreakpointState);
      routerEvents$.next(new NavigationEnd(1, '/dashboard', '/dashboard'));

      await fixture.whenStable();
      fixture.detectChanges();

      expect(router.navigate).toHaveBeenCalledWith(['/create-company']);
    });

    it('should NOT navigate if not logged in', async () => {
      fixture.detectChanges();

      mockIsLoggedIn$.next(false);
      mockCurrentCompanyId$.next(null);
      mockBreakpointState$.next({ matches: false, breakpoints: {} } as BreakpointState);
      routerEvents$.next(new NavigationEnd(1, '/dashboard', '/dashboard'));

      await fixture.whenStable();
      fixture.detectChanges();

      expect(router.navigate).not.toHaveBeenCalled();
    });

    it('should NOT navigate if companyId exists', async () => {
      fixture.detectChanges();

      mockIsLoggedIn$.next(true);
      mockCurrentCompanyId$.next('company123');
      mockBreakpointState$.next({ matches: false, breakpoints: {} } as BreakpointState);
      routerEvents$.next(new NavigationEnd(1, '/dashboard', '/dashboard'));

      await fixture.whenStable();
      fixture.detectChanges();

      expect(router.navigate).not.toHaveBeenCalled();
    });

    it('should NOT navigate if already on /create-company', async () => {
      fixture.detectChanges();

      mockIsLoggedIn$.next(true);
      mockCurrentCompanyId$.next(null);
      mockBreakpointState$.next({ matches: false, breakpoints: {} } as BreakpointState);
      routerEvents$.next(new NavigationEnd(1, '/create-company', '/create-company'));

      await fixture.whenStable();
      fixture.detectChanges();

      expect(router.navigate).not.toHaveBeenCalled();
    });
  });
});
