import { Component, inject, OnInit, OnDestroy } from '@angular/core';
import { BreakpointObserver, Breakpoints } from '@angular/cdk/layout';
import { AsyncPipe } from '@angular/common';
import { MatToolbarModule } from '@angular/material/toolbar';
import { MatButtonModule } from '@angular/material/button';
import { MatSidenavModule } from '@angular/material/sidenav';
import { MatListModule } from '@angular/material/list';
import { MatIconModule } from '@angular/material/icon';
import { Observable, Subject } from 'rxjs';
import { map, shareReplay, filter, takeUntil } from 'rxjs/operators';
import { Router, RouterModule, NavigationEnd } from '@angular/router';
import { AuthService } from '../../auth/auth.service';

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
  //  // Ensure this component is standalone if not already part of a module
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
    // Listen to router events and check signals synchronously
    this.router.events
      .pipe(
        filter((event) => event instanceof NavigationEnd),
        takeUntil(this.destroy$)
      )
      .subscribe(async (event) => {
        const isLoggedIn = this.authService.isLoggedInSignal();
        const companyId = this.authService.currentCompanyIdSignal();
        const currentUrl = (event as NavigationEnd).urlAfterRedirects;
        if (isLoggedIn && !companyId && currentUrl !== '/create-company') {
          if (currentUrl.startsWith('/auth/')) {
            return;
          }
          console.log(
            'User logged in but no company ID, redirecting to /create-company'
          );
          await this.router.navigate(['/create-company']);
        }
      });
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }

  logout(): void {
    this.authService.logout(); // AuthService logout already navigates to /login
  }
}
