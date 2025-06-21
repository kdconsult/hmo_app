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
  - `[x]` Create `AuthService` to handle all HTTP communication with the backend authentication service.
  - `[x]` Implement `login()` method.
  - `[x]` Implement `register()` method.
  - `[x]` Implement `logout()` method.
  - `[x]` Implement JWT storage and retrieval (using localStorage).
  - `[x]` Implement `isLoggedIn()` observable/signal for reactive state checking.
- **UI Components:**
  - `[x]` Create `LoginComponent` with a form for email and password.
  - `[x]` Create `RegisterComponent` with a form for user registration details.
  - `[x]` Create a shared `auth` layout/container components.
    - `[x]` One for anonymous user.
    - `[x]` One for authenticated (with navigation drower)
- **Routing:**
  - `[x]` Create an `auth.guard.ts` to protect routes that require a logged-in user.
  - `[x]` Define routes for `/login` and `/register`.
  - `[x]` Apply the auth guard to protected application routes (e.g., `/dashboard`).
- **Configuration:**
  - `[x]` Configure `provideHttpClient` in `app.config.ts`. This is required for the `AuthService` to communicate with the dedicated REST-based authentication service. Other data services will use a GraphQL client as per the data layer strategy.
- **Token Security:**
  - `[x]` Add the `jwt-decode` library to handle JWT parsing on the client-side.
  - `[x]` Update `AuthService.isLoggedIn()` to use `jwt-decode` to check the token's expiration date. This ensures that only users with valid, non-expired tokens are considered authenticated.

---

## 2. Advanced Authentication & Onboarding

This section details the implementation of advanced authentication features and the initial user onboarding flow for creating a new company, as specified in `BLA_Module_AuthAndOnboarding_Frontend.md`.

### 2.1 UI Enhancements for Existing Components

- **Login Component (`/login`):**
  - `[ ]` Add a "Forgot Password?" link that navigates to the password reset request page.
  - `[ ]` Implement specific error handling for "Email Not Verified" status, providing an option to trigger the "Resend Verification Email" flow.
- **Registration Component (`/register`):**
  - `[ ]` Refactor the 'name' form control into `first_name` and `last_name` controls to match the BLA.
  - `[ ]` Add `terms_agreed` checkbox with a `Validators.requiredTrue` validator to the form.
    - `[ ]` Generate the 'Terms and Conditions' component with actual terms to read before agree to it.
  - `[ ]` Define the password compelxity rules as configurable object. Later in the project - this will be stored in the DB per company in settings column.
  - `[ ]` Enhance password validation to enforce complexity rules (e.g., uppercase, lowercase, number, symbol) beyond simple minimum length.
  - `[ ]` Display password complexity rules visually (e.g., as a tooltip or helper text).
  - `[ ]` Ensure API success/error messages are displayed clearly as per the BLA.

### 2.2 Email Verification Workflow

- **Routing & Component:**
  - `[ ]` Create a new route and component for `/verify-email-status`.
- **Logic:**
  - `[ ]` Implement logic to extract the `verification_token` from the URL query parameters on component load.
  - `[ ]` Create a method in `AuthService` to send the token to the `/verify-email` endpoint.
- **UI:**
  - `[ ]` Implement UI to show loading, success, and error states.
  - `[ ]` Provide a link to the login page upon successful verification.

### 2.3 Password Reset Workflow

- **Request Reset Component (`/request-password-reset`):**
  - `[ ]` Create a new route and component.
  - `[ ]` Build the form to collect the user's email address.
  - `[ ]` Implement `AuthService` method to call `/request-password-reset`.
  - `[ ]` Implement UI to always show a generic success message to prevent email enumeration.
- **Reset Password Component (`/reset-password`):**
  - `[ ]` Create a new route and component.
  - `[ ]` Build the form to collect the new password and confirmation.
  - `[ ]` Implement logic to extract the `reset_token` from the URL.
  - `[ ]` Implement `AuthService` method to call `/reset-password` with the token and new password.
  - `[ ]` Implement UI for loading, success (with redirect to login), and error states.

### 2.4 Token Refresh & Interceptor

- **Interceptor:**
  - `[ ]` Create a new `HttpInterceptor` to handle token refresh logic.
  - `[ ]` The interceptor should catch `401 Unauthorized` errors on API calls.
- **`AuthService` Logic:**
  - `[ ]` Create a `refreshToken()` method in `AuthService` that calls `/refresh-token`.
  - `[ ]` The method should handle storing the new `accessToken`.
- **Interceptor Logic:**
  - `[ ]` On a 401 error, call `authService.refreshToken()`.
  - `[ ]` On successful refresh, retry the original failed request with the new token.
  - `[ ]` If refresh fails, log the user out and redirect to the login page.

### 2.5 Initial Company Onboarding Workflow

- **Lookup Data Services:**
  - `[ ]` Create a new service (e.g., `LookupService`) to fetch data for form dropdowns (`countries`, `company_types`, etc.).
- **Onboarding Component (`/create-company`):**
  - `[ ]` Create a new route and component, protected by the `authGuard`.
  - `[ ]` Implement logic to redirect users here after login if they have no company.
  - `[ ]` Build the form to collect all company details as per the BLA.
- **`CompanyService` Logic:**
  - `[ ]` Create a new `CompanyService` with a `createCompany()` method.
  - `[ ]` This method will send the authenticated `POST` request to create the company.
- **UI & State Management:**
  - `[ ]` Handle success by redirecting to the new company dashboard.
  - `[ ]` Implement logic to update the stored JWT if the backend returns a new one with company context.
