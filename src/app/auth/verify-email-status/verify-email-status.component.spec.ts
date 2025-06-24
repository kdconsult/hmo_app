import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router, convertToParamMap } from '@angular/router';
import { of, throwError, Subject } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { provideNoopAnimations } from '@angular/platform-browser/animations';
import { provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { vi, describe, it, expect, beforeEach, afterEach, Mock } from 'vitest';

import { VerifyEmailStatusComponent } from './verify-email-status.component';
import { AuthService } from '../auth.service';

// Keeping original Material Modules to respect original structure
import { MatCardModule } from '@angular/material/card';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';

describe('VerifyEmailStatusComponent', () => {
  let component: VerifyEmailStatusComponent;
  let fixture: ComponentFixture<VerifyEmailStatusComponent>;
  let authService: AuthService;
  let router: Router;

  const mockToken = 'test-verification-token';

  const configureTestBed = async (queryParams: Record<string, any>) => {
    await TestBed.configureTestingModule({
      imports: [
        VerifyEmailStatusComponent,
        MatCardModule,
        MatProgressSpinnerModule,
        MatButtonModule,
        MatIconModule,
      ],
      providers: [
        provideZonelessChangeDetection(),
        provideRouter([{ path: 'login', component: class {} }]),
        provideNoopAnimations(),
        {
          provide: AuthService,
          useValue: { verifyEmailToken: vi.fn() },
        },
        {
          provide: ActivatedRoute,
          useValue: {
            queryParamMap: of(convertToParamMap(queryParams)),
          },
        },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(VerifyEmailStatusComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService);
    router = TestBed.inject(Router);
    vi.spyOn(router, 'navigate');
  };

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('should create', async () => {
    await configureTestBed({ token: mockToken });
    fixture.detectChanges();
    expect(component).toBeTruthy();
  });

  it('should show loading state initially and call verifyEmailToken', async () => {
    await configureTestBed({ token: mockToken });
    // This mock will keep the observable pending until we complete it
    const pendingApi = new Subject<void>();
    (authService.verifyEmailToken as Mock).mockReturnValue(
      pendingApi.asObservable()
    );

    fixture.detectChanges(); // ngOnInit
    await fixture.whenStable();

    // Assert initial state
    expect(component.isLoading()).toBe(true);
    expect(authService.verifyEmailToken).toHaveBeenCalledWith(mockToken);
    expect(component.verificationStatus()).toBe('pending');

    // Complete the API call
    pendingApi.next();
    pendingApi.complete();
    await fixture.whenStable();
    fixture.detectChanges();

    // Assert final state after API completion
    expect(component.isLoading()).toBe(false);
    expect(component.verificationStatus()).toBe('success');
  });

  it('should display success message and status on successful verification', async () => {
    await configureTestBed({ token: mockToken });
    (authService.verifyEmailToken as Mock).mockReturnValue(
      of({ message: 'Email verified' })
    );
    fixture.detectChanges();
    await fixture.whenStable();
    // fixture.detectChanges(); // Removed mistaken addition here

    expect(component.isLoading()).toBe(false);
    expect(component.verificationStatus()).toBe('success');
    expect(component.message()).toBe(
      'Email successfully verified! You can now log in.'
    );
  });

  it('should display error message if token is missing from URL', async () => {
    await configureTestBed({ token: null });
    fixture.detectChanges();
    await fixture.whenStable();

    expect(component.isLoading()).toBe(false);
    expect(component.verificationStatus()).toBe('error');
    expect(component.message()).toBe('Verification token not found in URL.');
    expect(authService.verifyEmailToken).not.toHaveBeenCalled();
  });

  it('should display error message on API failure (e.g., 400 invalid token)', async () => {
    await configureTestBed({ token: mockToken });
    const errorResponse = new HttpErrorResponse({ status: 400 });
    (authService.verifyEmailToken as Mock).mockReturnValue(
      throwError(() => errorResponse)
    );
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges(); // Additional detectChanges

    expect(component.isLoading()).toBe(false);
    expect(component.verificationStatus()).toBe('error');
    expect(component.message()).toBe(
      'Invalid or expired verification link. Please try registering again or request a new verification email.'
    );
  });

  it('should display specific error for 404 (token not found/used)', async () => {
    await configureTestBed({ token: mockToken });
    const errorResponse = new HttpErrorResponse({ status: 404 });
    (authService.verifyEmailToken as Mock).mockReturnValue(
      throwError(() => errorResponse)
    );
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges(); // Additional detectChanges
    expect(component.message()).toBe(
      'Verification token not found or already used.'
    );
  });

  it('should display specific error for 409 (already verified)', async () => {
    await configureTestBed({ token: mockToken });
    const errorResponse = new HttpErrorResponse({ status: 409 });
    (authService.verifyEmailToken as Mock).mockReturnValue(
      throwError(() => errorResponse)
    );
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges(); // Additional detectChanges
    expect(component.message()).toBe('This email is already verified.');
  });

  it('should navigate to login on navigateToLogin() call', async () => {
    await configureTestBed({ token: mockToken });
    fixture.detectChanges();
    component.navigateToLogin();
    expect(router.navigate).toHaveBeenCalledWith(['/login']);
  });
});
