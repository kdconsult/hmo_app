import { Routes } from '@angular/router';
import { AnonymousLayoutComponent } from '@/layouts/anonymous-layout.component';
import { AuthenticatedLayoutComponent } from '@/layouts/authenticated-layout/authenticated-layout.component';
import { authGuard } from '@/auth/auth.guard';
import { LoginComponent } from '@/auth/login/login.component';
import { RegisterComponent } from '@/auth/register/register.component';
import { DashboardComponent } from '@/dashboard/dashboard.component';

export const routes: Routes = [
  // Redirect empty path to '/dashboard'. The authGuard on the dashboard route
  // will handle redirection to the login page if the user is not authenticated.
  { path: '', redirectTo: '/dashboard', pathMatch: 'full' },

  // Routes for anonymous users
  {
    path: '',
    component: AnonymousLayoutComponent,
    children: [
      {
        path: 'login',
        component: LoginComponent,
      },
      {
        path: 'register',
        component: RegisterComponent,
      },
    ],
  },

  // Routes for authenticated users
  {
    path: '',
    component: AuthenticatedLayoutComponent,
    canActivate: [authGuard],
    children: [
      {
        path: 'dashboard',
        component: DashboardComponent,
      },
      // Add other authenticated routes here, e.g.:
      // { path: 'partners', component: PartnersComponent },
      // { path: 'products', component: ProductsComponent },
    ],
  },

  // Wildcard route should redirect to the dashboard.
  // This handles any routes that don't match the ones defined above.
  { path: '**', redirectTo: '/dashboard', pathMatch: 'full' },
];
