## BLA_Module_AuthAndOnboarding_Frontend.md

**Document Version:** 1.0
**Date:** 16.06.2025
**Primary Audience:** Frontend Development Team
**Purpose:** This document outlines the frontend responsibilities, user interface requirements, client-side logic, and API interactions for User Authentication and Onboarding in Hyper M v2.

**1.F Overview & Key Goals for Frontend**

1.  Implement intuitive and responsive user interfaces for registration, login, email verification, password reset, and initial company creation.
2.  Ensure robust client-side validation for all user inputs to provide immediate feedback and reduce backend load.
3.  Securely manage JWTs (Access and Refresh Tokens) received from the backend.
4.  Handle API responses gracefully, displaying appropriate success or error messages and managing user redirection.
5.  Facilitate a smooth onboarding experience for users setting up their first company.

**2.F Core Entities & UI-Relevant Data**
_(Frontend needs to know what data to display or collect, and how statuses impact the UI)_

1.  **users**:
    - Fields to collect/display: `first_name`, `last_name`, `email`.
    - Status to react to: `email_verified` (e.g., to prompt for verification or allow login).
2.  **companies** (during initial creation):
    - Fields to collect: `name` (company_name), `eik` (company_eik), `country_id` (company_country_id), `company_type_id`, `default_locale_id` (company_default_locale_id), `default_currency_id` (company_default_currency_id).
    - Optional fields to collect for default location: `address_line1`, `city`, `post_code`, `region_name`.
3.  **Lookup Data (for dropdowns/selection)**:
    - `countries`: For selecting company country.
    - `company_types`: For selecting company type.
    - `locales`: For selecting company default locale.
    - `currencies`: For selecting company default currency (ideally filtered by selected country).

**3.F Key Workflows & Processes (Frontend Implementation)**

**3.1.F Workflow: New User Registration**

1. **Trigger / UI Entry Point:**
   _ User navigates to the public registration page (e.g., `/register`).
   _ User interacts with the registration form.
2. **Required Inputs (Collected via Form):**
   _ `first_name` (TEXT)
   _ `last_name` (TEXT)
   _ `email` (TEXT, valid email format)
   _ `password` (TEXT, meeting complexity rules)
   _ `password_confirmation` (TEXT, must match `password`)
   _ Agreement to Terms of Service & Privacy Policy (BOOLEAN checkbox, must be `TRUE`)
3. **User Interface Requirements:**
   _ Clear input fields for all required data.
   _ Display password complexity requirements visually or as tooltips.
   _ Real-time client-side validation for:
   _ Email format.
   _ Password complexity (e.g., min length, character types).
   _ Password matching `password_confirmation`.
   _ Required fields not empty.
   _ Link to Terms of Service & Privacy Policy documents.
   _ Checkbox for agreement. Must be checked to enable submission.
   _ Visual loading indicator during form submission.
   \_ Display clear success or error messages from the API.
4. **Client-Side Logic & API Interaction:**
5. Perform client-side validation (as per 3.1.F.3). If validation fails, display errors and prevent submission.
6. On submit, send a `POST` request to `[Auth_Service_Base_URL]/register` with the form data:

   ```json
   {
     "first_name": "...",
     "last_name": "...",
     "email": "...",
     "password": "...",
     "password_confirmation": "...", // May not be needed by backend if password already validated against rules
     "terms_agreed": true
   }
   ```

   `

7. Handle API Response:

   - **Success (e.g., 201 Created):** Display message: "Registration successful! Please check your email ([user_email]) to verify your account." Do NOT automatically log in the user.
     -. **Error (e.g., 400 Bad Request - Validation, 409 Conflict - Email Exists):** Display specific error messages provided by the backend (e.g., "Email address already in use," "Password does not meet complexity requirements").

8. **Post-conditions (Frontend):**
   - User is shown a success/error message. \* User remains on the registration page or is redirected to a page indicating to check their email.

**3.2.F Workflow: Email Verification**

1. **Trigger / UI Entry Point:**

   - User clicks the verification link from their email, navigating to e.g., `https://[app_domain]/verify-email?token=[verification_token]`.
   - Frontend page (e.g., `/verify-email-status`) loads, extracts `token` from URL.

2. **User Interface Requirements:**

   - Display a loading state while verification is in progress.
   - Display clear success message: "Email successfully verified! You can now log in." with a button/link to the login page (`/login`).
   - Display clear error messages: "Invalid or expired verification link. Please try registering again or request a new verification email if applicable."

3. **Client-Side Logic & API Interaction:**
4. On page load, extract the `verification_token` from the URL query parameters.
5. Send a `POST` request to `[Auth_Service_Base_URL]/verify-email` with the token:
   ```json
   {
     "token": "[verification_token]"
   }
   ```
   `
6. Handle API Response:

   - **Success (e.g., 200 OK):** Display success message and link/button to login page.
   - **Error (e.g., 400 Bad Request, 404 Not Found):** Display appropriate error message.

   4. **Post-conditions (Frontend):**

   - User is informed of verification status and guided to login if successful.

**3.3.F Workflow: User Login** 1. **Trigger / UI Entry Point:**
_ User navigates to the login page (e.g., `/login`).
_ User interacts with the login form. 2. **Required Inputs (Collected via Form):**
_ `email` (TEXT)
_ `password` (TEXT) 3. **User Interface Requirements:**
_ Input fields for email and password.
_ "Forgot Password?" link navigating to password reset request page.
_ Visual loading indicator during form submission.
_ Display clear error messages from the API. 4. **Client-Side Logic & API Interaction:** 1. Perform basic client-side validation (e.g., fields not empty). 2. On submit, send a `POST` request to `[Auth_Service_Base_URL]/login` with credentials:
`json
             {
               "email": "...",
               "password": "..."
             }
             ` 3. Handle API Response:
_ **Success (e.g., 200 OK):**
_ Backend returns JWT Access Token and (optionally) Refresh Token.
`json
                 {
                   "accessToken": "...",
                   "refreshToken": "..." // Optional
                 }
                 `
_ Securely store the `accessToken` (e.g., in memory, `localStorage` for SPAs - consider security implications) and `refreshToken` (e.g., in an `HttpOnly` cookie if set by backend, or `localStorage` if necessary).
_ Redirect user to their dashboard (e.g., `/dashboard`) or to the "Create Company" flow if they have no active company memberships.
_ **Error (e.g., 401 Unauthorized - Invalid Credentials, 403 Forbidden - Email Not Verified):** Display specific error messages. If "Email Not Verified," provide a "Resend Verification Email" option/link (triggers Workflow 3.8.F). 5. **Post-conditions (Frontend):**
_ If successful, tokens are stored, user is redirected. \* If unsuccessful, error message is displayed.

**3.4.F Workflow: Access Token Refresh** 1. **Trigger / Client Logic:**
_ An API request using the `accessToken` fails with a 401 Unauthorized (or client proactively checks `accessToken` expiry).
_ Client possesses a `refreshToken`. 2. **User Interface Requirements:**
_ This process should be transparent to the user if successful.
_ If refresh fails, gracefully log the user out (clear tokens, redirect to `/login`). 3. **Client-Side Logic & API Interaction:** 1. If `accessToken` is expired/invalid and `refreshToken` exists, send a `POST` request to `[Auth_Service_Base_URL]/refresh-token`:
_ If `refreshToken` is in an `HttpOnly` cookie, it will be sent automatically.
_ If managed by client:
`json
                 {
                   "refreshToken": "..."
                 }
                 ` 2. Handle API Response:
_ **Success (e.g., 200 OK):**
_ Backend returns a new `accessToken` and (optionally) a new `refreshToken`.
`json
                 {
                   "accessToken": "...",
                   "refreshToken": "..." // Optional, if rotation is used
                 }
                 `
_ Update stored tokens.
_ Retry the original failed API request with the new `accessToken`.
_ **Error (e.g., 401 Unauthorized/403 Forbidden - Invalid/Expired Refresh Token):**
_ Clear all stored tokens.
_ Redirect user to `/login`. 4. **Post-conditions (Frontend):**
_ Session extended transparently, or user is logged out.

**3.5.F Workflow: User Logout** 1. **Trigger / UI Entry Point:**
_ User clicks a "Logout" button/link. 2. **User Interface Requirements:**
_ Clear logout action. Optional confirmation prompt. 3. **Client-Side Logic & API Interaction:** 1. (Optional but Recommended) Send a `POST` request to `[Auth_Service_Base_URL]/logout`. This allows server-side revocation of the refresh token.
_ If `refreshToken` is in `HttpOnly` cookie, it's sent. If client-managed, it might need to be sent. 2. Irrespective of API call success/failure:
_ Delete/clear `accessToken` from client storage.
_ Delete/clear `refreshToken` from client storage (if not `HttpOnly`). 3. Redirect user to login page (`/login`) or public landing page. 4. **Post-conditions (Frontend):**
_ Tokens are cleared from client. User is redirected.

**3.6.F Workflow: Forgot Password / Password Reset**
**3.6.1.F Sub-Workflow: Request Password Reset** 1. **Trigger / UI Entry Point:** User clicks "Forgot Password?" link (e.g., on login page), navigates to `/request-password-reset` page. 2. **Required Inputs (Collected via Form):** `email` (TEXT). 3. **User Interface Requirements:**
_ Input field for email.
_ Client-side validation for email format.
_ On submission, display a generic success message: "If an account exists for [user_email], a password reset link has been sent." (Do NOT confirm if email exists).
_ Display error for invalid email format _before_ submission. 4. **Client-Side Logic & API Interaction:** 1. Validate email format client-side. 2. Send `POST` request to `[Auth_Service_Base_URL]/request-password-reset` with:
`json
                { "email": "..." }
                ` 3. Handle API Response:
_ **Always display the generic success message** mentioned in 3.6.1.F.3, regardless of backend response code (e.g., 200 OK or 202 Accepted), to prevent email enumeration. Backend will handle the logic quietly.
**3.6.2.F Sub-Workflow: Reset Password** 1. **Trigger / UI Entry Point:** User clicks link in email, navigates to `https://[app_domain]/reset-password?token=[reset_token]`. Page extracts `token`. 2. **Required Inputs (Collected via Form):** `new_password`, `confirm_new_password`. 3. **User Interface Requirements:**
_ Password input fields for `new_password` and `confirm_new_password`.
_ Display password complexity requirements.
_ Client-side validation for password complexity and match.
_ On success: "Password successfully reset. You can now log in." with link/button to `/login`.
_ On error: Display messages like "Invalid or expired password reset link," "Passwords do not match," or "Password does not meet complexity." 4. **Client-Side Logic & API Interaction:** 1. Extract `reset_token` from URL. 2. Perform client-side validation for passwords. 3. Send `POST` request to `[Auth_Service_Base_URL]/reset-password` with:
`json
                {
                  "token": "[reset_token]",
                  "new_password": "...",
                  "confirm_new_password": "..."
                }
                ` 4. Handle API Response:
_ **Success (e.g., 200 OK):** Display success message and direct to login.
_ **Error (e.g., 400 Bad Request):** Display specific error.

**3.7.F Workflow: Initial Company Onboarding (Creating the First Company)** 1. **Trigger / UI Entry Point:**
_ User logs in, and frontend determines (e.g., via an API call or JWT claim) they have no active company. Redirect to `/create-company` page.
_ Or, user navigates to a "Create Company" section. 2. **Required Inputs (Collected via Form):**
_ `company_name` (TEXT)
_ `company_eik` (TEXT)
_ `company_country_id` (UUID from dropdown)
_ `company_type_id` (UUID from dropdown)
_ `company_default_locale_id` (UUID from dropdown)
_ `company_default_currency_id` (UUID from dropdown, filtered by country)
_ Optional: `company_address_line1`, `company_city`, `company_post_code`, `company_region_name` (for default location). 3. **User Interface Requirements:**
_ Potentially a multi-step form (e.g., Company Details, Default Location).
_ Dropdowns populated by API calls to fetch `countries`, `company_types`, `locales`, `currencies`.
_ Currency dropdown filtered based on selected country.
_ Clear indication of required fields. Client-side validation.
_ Inform user about automatic free trial: "Your new company will start with a 30-day free trial...".
_ Loading indicator on submission. 4. **Client-Side Logic & API Interaction:** 1. Fetch data for dropdowns (countries, types, locales, currencies) from respective API endpoints (e.g., `/api/countries`, `/api/company-types`, etc. - backend to define these). 2. Perform client-side validation on all inputs. 3. On submit, send `POST` request to `[Your_App_Base_URL]/api/companies` (or a dedicated company creation endpoint, e.g., `/api/onboarding/create-company` - requires authenticated user, JWT sent in header).
`json
             {
               "company_name": "...",
               "company_eik": "...",
               "company_country_id": "...",
               "company_type_id": "...",
               "company_default_locale_id": "...",
               "company_default_currency_id": "...",
               "default_location": { // Optional, structure TBD with backend
                 "address_line1": "...",
                 "city": "...",
                 "post_code": "...",
                 "region_name": "..."
               }
             }
             ` 4. Handle API Response:
_ **Success (e.g., 201 Created):**
_ Backend may return new company details and potentially an updated JWT with new `x-hasura-company-id` and `x-hasura-default-role` ('admin' for this company). If so, update stored JWT.
_ Display success: "Company '[Company Name]' created successfully!"
_ Redirect to the new company's dashboard (e.g., `/dashboard?company_id=[new_company_id]`). Subsequent API calls to Hasura/backend should include `X-Hasura-Company-ID` and correct role.
_ **Error (e.g., 400 Bad Request - Validation, 409 Conflict - EIK exists):** Display specific error messages. 5. **Post-conditions (Frontend):** \* User is redirected to company dashboard. Client stores necessary company context for future API calls.

**3.8.F Workflow: Resend Email Verification Link** 1. **Trigger / UI Entry Point:**
_ User sees an error message during login (Workflow 3.3.F) "Please verify your email" with a "Resend Verification Email" link/button.
_ User clicks the link/button, potentially pre-filling the email.
_ Alternatively, a dedicated page `/resend-verification` where user enters email. 2. **Required Inputs (Collected or Pre-filled):** `email` (TEXT). 3. **User Interface Requirements:**
_ If a form, input field for email and client-side validation for format.
_ On action, display message: "A new verification email has been sent to [user_email]. Please check your inbox."
_ Error if email format is invalid. 4. **Client-Side Logic & API Interaction:** 1. Client-side validate email format if entered manually. 2. Send `POST` request to `[Auth_Service_Base_URL]/resend-verification-email` with:
`json
             { "email": "..." }
             ` 3. Handle API Response:
_ **Success (e.g., 200 OK):** Display success message.
_ **Error (e.g., 400/404 if email not found and backend chooses to reveal, or 422 if already verified):** Display appropriate message from backend, or a generic success message as per backend strategy to avoid enumeration. \* If backend confirms "Already Verified": "This email address has already been verified. You can proceed to login."

**4.F Token Management**

1.  **Access Token:** Store securely (e.g., JavaScript variable in memory for SPA, `localStorage` with XSS considerations). Include in `Authorization: Bearer [accessToken]` header for authenticated API calls.
2.  **Refresh Token:** If returned and managed by frontend (not `HttpOnly` cookie), store securely (e.g., `localStorage`). Use only to request new access tokens.
3.  **Clearing Tokens:** Clear all tokens on logout and on failed refresh token attempts.

**5.F API Endpoints (Summary for Frontend)**
_(This is a summary; backend document will be the source of truth for exact request/response schemas)_

- `POST /register`
- `POST /verify-email`
- `POST /login`
- `POST /refresh-token`
- `POST /logout` (Optional, for server-side refresh token invalidation)
- `POST /request-password-reset`
- `POST /reset-password`
- `POST /resend-verification-email`
- `POST /api/companies` (or similar for company creation, requires auth)
- `GET /api/countries`, `GET /api/company-types`, `GET /api/locales`, `GET /api/currencies` (for populating forms)

**6.F Open Questions / Future Considerations (Frontend Perspective)**

1.  Specific UI designs for loading states, error messages, and form layouts.
2.  Password complexity rules display and real-time feedback mechanisms.
3.  Exact mechanism/timing for fetching lookup data (countries, types, etc.).
4.  Strategy for handling "Remember Me" functionality and its impact on token storage/lifespan.
5.  How to handle JWT updates post-company creation if the backend returns a new one.
