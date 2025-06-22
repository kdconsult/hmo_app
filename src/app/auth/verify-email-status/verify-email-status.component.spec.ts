import { ComponentFixture, TestBed, fakeAsync, tick } from '@angular/core/testing';
import { ActivatedRoute, Router } from '@angular/router';
import { of, throwError } from 'rxjs';
import { HttpErrorResponse } from '@angular/common/http';
import { NoopAnimationsModule } from '@angular/platform-browser/animations';

import { VerifyEmailStatusComponent } from './verify-email-status.component';
import { AuthService } from '../auth.service';

// Material Modules
import { MatCardModule } from '@angular/material/card';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';

class MockAuthService {
  verifyEmailToken = jest.fn();
}

class MockRouter {
  navigate = jest.fn();
}

describe('VerifyEmailStatusComponent', () => {
  let component: VerifyEmailStatusComponent;
  let fixture: ComponentFixture<VerifyEmailStatusComponent>;
  let authService: MockAuthService;
  let router: MockRouter;
  let activatedRoute: ActivatedRoute;

  const mockToken = 'test-verification-token';

  const setupComponent = (queryParams: Record<string, string | null>) => {
    TestBed.configureTestingModule({
      imports: [
        VerifyEmailStatusComponent, // Standalone
        NoopAnimationsModule,
        MatCardModule, MatProgressSpinnerModule, MatButtonModule, MatIconModule
      ],
      providers: [
        { provide: AuthService, useClass: MockAuthService },
        { provide: Router, useClass: MockRouter },
        {
          provide: ActivatedRoute,
          useValue: {
            queryParamMap: of(new Map(Object.entries(queryParams))),
          },
        },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(VerifyEmailStatusComponent);
    component = fixture.componentInstance;
    authService = TestBed.inject(AuthService) as unknown as MockAuthService;
    router = TestBed.inject(Router) as unknown as MockRouter;
    activatedRoute = TestBed.inject(ActivatedRoute);
  };

  it('should create', () => {
    setupComponent({ token: mockToken });
    fixture.detectChanges(); // ngOnInit is called here
    expect(component).toBeTruthy();
  });

  it('should show loading state initially and call verifyEmailToken with token from route', fakeAsync(() => {
    setupComponent({ token: mockToken });
    authService.verifyEmailToken.mockReturnValue(of({}).pipe()); // Keep pending

    expect(component.isLoading()).toBe(true); // Should be true before ngOnInit runs from detectChanges
    fixture.detectChanges(); // ngOnInit
    tick(); // Process microtasks like queryParamMap subscription

    expect(component.isLoading()).toBe(true); // Still true as API call is pending
    expect(authService.verifyEmailToken).toHaveBeenCalledWith(mockToken);

    // Manually complete the observable if needed, or flush if it was a httpMock
    // For this mock, the pipe() will keep it pending.
  }));


  it('should display success message and status on successful verification', fakeAsync(() => {
    setupComponent({ token: mockToken });
    authService.verifyEmailToken.mockReturnValue(of({ message: 'Email verified' }));
    fixture.detectChanges(); // ngOnInit
    tick(); // process observable

    expect(component.isLoading()).toBe(false);
    expect(component.verificationStatus()).toBe('success');
    expect(component.message()).toBe('Email successfully verified! You can now log in.');
  }));

  it('should display error message if token is missing from URL', fakeAsync(() => {
    setupComponent({ token: null }); // No token
    fixture.detectChanges(); // ngOnInit
    tick();

    expect(component.isLoading()).toBe(false);
    expect(component.verificationStatus()).toBe('error');
    expect(component.message()).toBe('Verification token not found in URL.');
    expect(authService.verifyEmailToken).not.toHaveBeenCalled();
  }));

  it('should display error message on API failure (e.g., 400 invalid token)', fakeAsync(() => {
    setupComponent({ token: mockToken });
    const errorResponse = new HttpErrorResponse({ status: 400, error: { message: 'Token invalid' } });
    authService.verifyEmailToken.mockReturnValue(throwError(() => errorResponse));
    fixture.detectChanges(); // ngOnInit
    tick();

    expect(component.isLoading()).toBe(false);
    expect(component.verificationStatus()).toBe('error');
    expect(component.message()).toBe('Invalid or expired verification link. Please try registering again or request a new verification email.');
  }));

  it('should display specific error for 404 (token not found/used)', fakeAsync(() => {
    setupComponent({ token: mockToken });
    const errorResponse = new HttpErrorResponse({ status: 404 });
    authService.verifyEmailToken.mockReturnValue(throwError(() => errorResponse));
    fixture.detectChanges();
    tick();
    expect(component.message()).toBe('Verification token not found or already used.');
  }));

    it('should display specific error for 409 (already verified)', fakeAsync(() => {
    setupComponent({ token: mockToken });
    const errorResponse = new HttpErrorResponse({ status: 409 });
    authService.verifyEmailToken.mockReturnValue(throwError(() => errorResponse));
    fixture.detectChanges();
    tick();
    expect(component.message()).toBe('This email is already verified.');
  }));


  it('should navigate to login on navigateToLogin() call', () => {
    setupComponent({ token: mockToken });
    fixture.detectChanges();
    component.navigateToLogin();
    expect(router.navigate).toHaveBeenCalledWith(['/login']);
  });
});
