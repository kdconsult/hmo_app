import { inject } from '@angular/core';
import { CanActivateFn, createUrlTreeFromSnapshot } from '@angular/router';
import { AuthService } from '@/auth/auth.service';

export const authGuard: CanActivateFn = (route, _state) => {
  const authService = inject(AuthService);

  return authService.isLoggedIn
    ? true
    : createUrlTreeFromSnapshot(route, ['/login']);
};
