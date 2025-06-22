import { Component, inject, OnInit, OnDestroy } from '@angular/core'; // Import OnInit, OnDestroy
import { BreakpointObserver, Breakpoints } from '@angular/cdk/layout';
import { AsyncPipe } from '@angular/common';
import { MatToolbarModule } from '@angular/material/toolbar';
import { MatButtonModule } from '@angular/material/button';
import { MatSidenavModule } from '@angular/material/sidenav';
import { MatListModule } from '@angular/material/list';
import { MatIconModule } from '@angular/material/icon';
import { Observable } from 'rxjs';
import { map, shareReplay, takeUntil, filter, tap, switchMap } from 'rxjs/operators';
import { Router, RouterModule, NavigationEnd } from '@angular/router';
import { AuthService } from '@/auth/auth.service';
import { Subject, combineLatest } from 'rxjs'; // Import Subject and combineLatest

@Component({
  selector: 'app-authenticated-layout',
  templateUrl: './authenticated-layout.component.html',
  styleUrl: './authenticated-layout.component.scss',
  imports: [
    MatToolbarModule,
    MatButtonModule,
    MatSidenavModule,
    MatListModule,
    MatIconModule,
    AsyncPipe,
    RouterModule,
  ],
  // standalone: true, // Ensure this component is standalone if not already part of a module
})
export class AuthenticatedLayoutComponent implements OnInit, OnDestroy {
  private breakpointObserver = inject(BreakpointObserver);
  private authService = inject(AuthService);
  private router = inject(Router);
  private destroy$ = new Subject<void>();

  isHandset$: Observable<boolean> = this.breakpointObserver
    .observe(Breakpoints.Handset)
    .pipe(
      map((result) => result.matches),
      shareReplay()
    );

  ngOnInit(): void {
    combineLatest([
      this.authService.isLoggedIn$,
      this.authService.currentCompanyId$,
      this.router.events.pipe(filter(event => event instanceof NavigationEnd))
    ])
    .pipe(
      takeUntil(this.destroy$),
      filter(([isLoggedIn, companyId, navEvent]) => {
        // Only proceed if logged in and the navigation event is available
        // companyId can be null, that's what we check for
        return isLoggedIn && navEvent instanceof NavigationEnd;
      }),
      // switchMap here to avoid issues if companyId$ emits multiple times quickly
      // though with current setup, it emits on token set/clear.
      switchMap(async ([isLoggedIn, companyId, navEvent]) => {
        const currentUrl = (navEvent as NavigationEnd).urlAfterRedirects;
        if (isLoggedIn && !companyId && currentUrl !== '/create-company') {
          // Check if not already trying to navigate to create-company to avoid loops
          // Also check if not already on a public-like page if any exist within auth layout (none currently)
          if (currentUrl.startsWith('/auth/')) { // Example: if /auth/profile was under AuthenticatedLayout
            return; // Don't redirect from other auth pages
          }
          console.log('User logged in but no company ID, redirecting to /create-company');
          await this.router.navigate(['/create-company']);
        }
      })
    )
    .subscribe();
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  logout(): void {
    this.authService.logout(); // AuthService logout already navigates to /login
  }
}
