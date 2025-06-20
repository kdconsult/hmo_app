# Project Roadmap: hmo_app (Angular Frontend)

This document outlines the development plan, features, and status for the main Angular application.

---

## 1. Authentication Layer

The foundation for user access and security. Handles user login, registration, and session management.

### High-Level Requirements:

- Users must be able to log in with an email and password.
- Users must be able to register for a new account.
- The application must protect routes that require authentication.
- The user's login state must be managed and accessible throughout the app.

### Implementation Plan:

**Status Key:** `[ ]` - To Do, `[/]` - In Progress, `[x]` - Done

- **Core Service:**
  - `[ ]` Create `AuthService` to handle all HTTP communication with the backend authentication service.
  - `[ ]` Implement `login()` method.
  - `[ ]` Implement `register()` method.
  - `[ ]` Implement `logout()` method.
  - `[ ]` Implement JWT storage and retrieval (using localStorage).
  - `[ ]` Implement `isLoggedIn()` observable/signal for reactive state checking.
- **UI Components:**
  - `[ ]` Create `LoginComponent` with a form for email and password.
  - `[ ]` Create `RegisterComponent` with a form for user registration details.
  - `[ ]` Create a shared `auth` layout/container component.
- **Routing:**
  - `[ ]` Create an `auth.guard.ts` to protect routes that require a logged-in user.
  - `[ ]` Define routes for `/login` and `/register`.
  - `[ ]` Apply the auth guard to protected application routes (e.g., `/dashboard`).
- **Configuration:**
  - `[ ]` Ensure `provideHttpClient` is configured in `app.config.ts` to enable the `AuthService`.
