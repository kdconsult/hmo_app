Business Logic Addendum: User Authentication & Onboarding

BLA_Module_AuthAndOnboarding.md

Document Version: 1.0 Date: \[16.06.2025\] Related DDLs: public.users, public.roles, public.companies, public.companie_translations, public.company_types, public.company_memberships, public.company_locations, public.company_location_translations, public.countries, public.locales, public.currencies. (Essentially, the core foundation entities) Primary Audience: Development Team

1. ### **Overview & Purpose**

   1. This BLA defines the business logic for new user registration, user login (authentication), and the initial onboarding process where a new user can create their first company within Hyper M v2.
   2. Key goals include:
      1. Securely registering and authenticating users.
      2. Ensuring a smooth process for users to set up their primary company.
      3. Establishing the foundational records for a new tenant (company) and the user's administrative role within it.

2. ### **Core Entities & Their States/Statuses relevant to this specific BLA.**

For "User Authentication & Onboarding," the key entities and their relevant statuses are:

1. users:

   1. Purpose: Represents a global user identity in the system.  
      2. Key fields for this BLA: email, password_hash, email_verified, first_name, last_name.  
      3. Status Lifecycle for email_verified (BOOLEAN):
      1. FALSE (Default on creation): Email has not yet been verified. User might have limited access or functionality.
      2. TRUE: Email has been successfully verified (e.g., by clicking a link sent to their email). User gains full access related to their basic account.
   2. companies:

      1. Purpose: Represents a tenant organization within Hyper M v2.
      2. Key fields for this BLA (during initial creation): name, eik, country_id, default_locale_id, default_currency_id, company_type_id.
      3. Status Lifecycle: Not a direct status field on companies relevant here, but its creation is a key outcome. deleted_at for soft delete later.
      4. Translations: Supports translations via public.company_translations. Translatable fields typically include name and legal_responsible_person. For general translation strategy, see \[Link to: Core_Principle_Translations.md\]. During initial company creation, translations are usually not managed; the primary data is entered in the company's default locale. Translation management is typically a subsequent administrative task.

   3. company_memberships:
      1. Purpose: Links a user to a company with a specific role and status.
      2. Key fields for this BLA: user_id, company_id, role_id, status.
      3. Status Lifecycle for status (company_membership_status_enum):
         1. active: For the user creating their own company, their membership is immediately active.
         2. (Other statuses like 'pending', 'inactive', 'removed' are more relevant for subsequent user management, which will be in "Company & User Management BLA").
   4. company_locations:
      1. Purpose: Represents an operational site for a company.
      2. Key fields for this BLA (for default location): company_id, name, address_line1, city, country_id, is_default \= TRUE.
      3. Status Lifecycle: deleted_at for soft delete. A default active location is created during company onboarding.
      4. Translations: Supports translations via public.company_location_translations. Translatable fields typically include name and address components. For general translation strategy, see \[Link to: Core_Principle_Translations.md\]. The default location created during onboarding will use names/addresses from the company's default locale.

2. ### **Key Workflows & Processes**

   1. Workflow: New User Registration

      1. Trigger / Entry Point:
         1. User navigates to the public registration page/form (e.g., /register).
         2. User submits the registration form.
      2. Pre-conditions / Required Inputs (from User):
         1. first_name (TEXT, NOT NULL)
         2. last_name (TEXT, NOT NULL)
         3. email (TEXT, NOT NULL, must be a valid email format)
         4. password (TEXT, NOT NULL, must meet complexity requirements)
         5. password_confirmation (TEXT, NOT NULL, must match password)
         6. Agreement to Terms of Service & Privacy Policy (BOOLEAN, must be TRUE)
      3. User Interface Considerations (Functional):
         1. Clear input fields for all required data.
         2. Real-time client-side validation for email format, password complexity, and password match.
         3. Link to Terms of Service & Privacy Policy documents.
         4. Checkbox for agreement.
         5. Loading indicator during submission.
         6. Clear success or error messages displayed to the user.
      4. Step-by-Step Logic & Rules:
         1. Client-Side Validation: Perform initial validation as per [3.1.3](?tab=t.0#heading=h.4x9634r8xefq). If fails, display errors to the user, do not submit to backend.
         2. Server-Side Submission: User submits the form data to the backend Authentication Service (dedicated Node.js service).
         3. Server-Side Input Validation:
         4. Verify all required fields are present and not empty.
         5. Validate email format again.
         6. Validate password against complexity rules (e.g., min length, character types \- these rules should be defined, perhaps in a Core_Principle_Security.md or an appendix).
         7. Verify password matches password_confirmation.
         8. Verify agreement to Terms/Policy is TRUE.
         9. If any server-side validation fails, return an appropriate error response (e.g., 400 Bad Request) with clear error messages.
         10. Check for Email Uniqueness:
             1. Query the public.users table to check if an active user (i.e., deleted_at IS NULL) already exists with the provided email.
             2. If email already exists, return an error (e.g., 409 Conflict \- "Email address already in use").
             3. Password Hashing:
                1. Generate a strong cryptographic hash of the user's password (e.g., using bcrypt or Argon2). Store only the hash (password_hash), never the plain text password.
             4. Create User Record:
                1. INSERT a new record into public.users table with:
                2. id: gen_random_uuid()
                3. first_name: Provided first_name
                4. last_name: Provided last_name
                5. email: Provided email (normalized, e.g., to lowercase)
                6. password_hash: The generated hash
                7. email_verified: FALSE (Default)
                8. created_at, updated_at: now()
             5. Generate Email Verification Token:
                1. Generate a secure, unique, time-limited token associated with the new user's ID and email.
                2. This token could be stored temporarily (e.g., in a separate table like email_verification_tokens with user_id, token, expiry) or be a JWT with an expiry claim.
             6. Send Verification Email:
                1. Construct an email verification link containing this token (e.g., [https://\[app_domain\]/verify-email?token=\[verification_token](https://[app_domain]/verify-email?token=[verification_token)\]).
                2. Send an email to the user's provided email address with this link and instructions to verify their account. This is handled by an Email Service.
      5. Post-conditions / Outputs:
         1. A new record exists in public.users with email_verified \= FALSE.
         2. A verification email has been dispatched to the user.
         3. User Feedback (UI): Display a success message to the user, e.g., "Registration successful\! Please check your email (\[user_email\]) to verify your account."
         4. The user is typically not logged in automatically at this stage. Login occurs after email verification or as a separate step. (This is a design choice \- some systems log users in immediately but restrict functionality until verification). For Hyper M, let's assume login requires verification first unless specified otherwise.
      6. Error Handling / Exceptional Flows: Invalid input format (client/server validation).
         1. Email already in use.
         2. Failure to send verification email (e.g., email service down \- system should ideally queue this or allow resend).
         3. Database errors during user creation.
      7. Permissions / Authorization Notes:
         1. This registration endpoint is publicly accessible.

   2. ### **Workflow: Email Verification**

      1. #### **Trigger / Entry Point:**

         1. User clicks the verification link received in their registration email (e.g., [https://\[app_domain\]/verify-email?token=\[verification_token](https://[app_domain]/verify-email?token=[verification_token)\]).

      2. Pre-conditions / Required Inputs:
         1. A valid, non-expired verification_token (as a URL query parameter).
      3. User Interface Considerations (Functional):
         1. A dedicated page (e.g., /verify-email-status) to display the outcome of the verification attempt.
         2. Clear success message (e.g., "Email successfully verified\! You can now log in.") with a link/button to the login page.
         3. Clear error messages for invalid/expired token or other issues.
      4. Step-by-Step Logic & Rules:
         1. Backend Request: The frontend makes a request to a dedicated backend endpoint (e.g., in the Authentication Service) passing the verification_token.
         2. Token Validation:
            1. The backend retrieves the verification_token.
            2. It checks the validity of the token:
            3. Is it well-formed?
            4. Does it exist in the temporary storage (e.g., email_verification_tokens table) or is it a valid JWT designed for this purpose?
            5. Has it expired?
            6. Does it correspond to an existing user in public.users whose email_verified is still FALSE?
            7. If the token is invalid, expired, or doesn't match a pending verification, return an error (e.g., "Invalid or expired verification link.").
         3. Update User Status:
            1. If the token is valid, retrieve the associated user_id.
            2. UPDATE the public.users record for this user_id:
               1. Set email_verified \= TRUE.
               2. Set updated_at \= now().
         4. Clean Up Token (If Applicable):
            1. If the token was stored in a temporary table (like email_verification_tokens), delete or mark the token record as used to prevent reuse.
      5. Post-conditions / Outputs:
         1. The users.email_verified field for the corresponding user is set to TRUE.
         2. The verification token is invalidated/consumed.
         3. User Feedback (UI): Display success message and direct user to login.
      6. Error Handling / Exceptional Flows:
      7. Token not found, invalid, or expired.
      8. User account associated with token not found or already verified.
      9. Database error during user update.
      10. Permissions / Authorization Notes:
          1. This verification endpoint is publicly accessible (as the token itself is the authorization mechanism).

   3. ### **Workflow: User Login**

      1. #### **Trigger / Entry Point:**

         1. User navigates to the login page/form (e.g., `/login`).
         2. User submits the login form.

      2. **Pre-conditions / Required Inputs (from User):**
         1. `email` (TEXT, NOT NULL)
         2. `password` (TEXT, NOT NULL)
      3. **User Interface Considerations (Functional):**
         1. Input fields for email and password.
         2. "Forgot Password?" link.
         3. Loading indicator during submission.
         4. Clear success (redirect) or error messages.
      4. **Step-by-Step Logic & Rules:**
         1. **Client-Side Validation:** Basic checks for non-empty fields.
         2. **Server-Side Submission:**
            1. User submits credentials to the backend Authentication Service.
         3. **Server-Side Input Validation:**
            1. Verify `email` and `password` are provided.
         4. **Retrieve User Record:**
            1. Query `public.users` table for a user with the provided `email` (normalized, e.g., to lowercase) and `deleted_at IS NULL`.
            2. If no user is found, return an authentication error (e.g., 401 Unauthorized \- "Invalid email or password."). **Do not indicate whether the email exists or the password was wrong to prevent email enumeration.**
         5. **Check Email Verification Status:**
            1. If the user record is found, check `users.email_verified`.
            2. If `email_verified` is `FALSE`, return an error (e.g., 403 Forbidden \- "Please verify your email address before logging in.") Optionally, provide a link/button to resend the verification email.
         6. **Verify Password:**
            1. Compare the provided `password` against the stored `users.password_hash` using the same hashing algorithm (e.g., bcrypt.compare).
            2. If the password does not match, return an authentication error (e.g., 401 Unauthorized \- "Invalid email or password.").
         7. **Issue JWT (JSON Web Token):**
            1. If the password matches and email is verified, generate a JWT.
            2. The JWT payload should contain essential claims for Hasura and application services:
               1. `sub` (Subject): [`users.id`](http://users.id)
               2. `iat` (Issued At): Current timestamp
               3. `exp` (Expiration Time): Future timestamp (e.g., 15 mins for access token, longer for refresh token)
               4. [`https://hasura.io/jwt/claims`](https://hasura.io/jwt/claims):
                  1. `x-hasura-allowed-roles`: An array of roles. For a global user not yet associated with a company, this might be a generic role like `['user']` or potentially empty until a company context is selected. (This needs more thought when company selection comes in).
                  2. `x-hasura-default-role`: The default role to use.
                  3. `x-hasura-user-id`: [`users.id`](http://users.id)
                  4. (Potentially other custom claims like `email`, `first_name` if needed by services, but keep payload lean).
                  5. Sign the JWT with a secret key known only to the Authentication Service and Hasura.
         8. **(Optional) Issue Refresh Token:**
            1. Generate a long-lived, secure refresh token. Store it securely (e.g., in an HTTPOnly cookie or in a database table associated with the user and device). This refresh token can be used to obtain new access JWTs without requiring the user to re-enter credentials.
      5. **Post-conditions / Outputs:**
         1. If successful:
            1. A JWT (access token) is returned to the client (e.g., in the response body or an HTTPOnly cookie).
            2. (Optional) A refresh token is issued.
            3. **User Feedback (UI):** User is typically redirected to their dashboard or the last visited page. The client application stores the JWT for subsequent API requests.
         2. If unsuccessful: An appropriate error message is displayed.
      6. **Error Handling / Exceptional Flows:**
         1. User not found.
         2. Incorrect password.
         3. Email not verified.
         4. Account locked (if implementing lockout policies after too many failed attempts \- future consideration).
         5. JWT signing errors.
      7. **Permissions / Authorization Notes:**
         1. Login endpoint is publicly accessible.

   4. **Workflow: Access Token Refresh**
      1. **3.4.1. Trigger / Entry Point:**
         1. Client application determines its current JWT Access Token is expired or nearing expiry (based on `exp` claim or a 401 response from an API).
         2. Client application possesses a valid, non-expired Refresh Token.
      2. **Pre-conditions / Required Inputs:**
         1. Valid `refresh_token` (typically sent in an HTTPOnly cookie or as part of a secure request body).
      3. **3.4.3. User Interface Considerations (Functional):**
         1. This process is usually transparent to the user.
         2. If refresh fails and the user is effectively logged out, the UI should gracefully handle this by redirecting to the login page.
      4. **Step-by-Step Logic & Rules:**
         1. **Client Request:** Client sends the `refresh_token` to a dedicated refresh endpoint on the Authentication Service (e.g., `/auth/refresh-token`).
         2. **Refresh Token Validation (Authentication Service):**
            1. Validate the received `refresh_token`:
               1. Is it well-formed?
               2. Does it exist in the secure refresh token store (e.g., database table linking refresh tokens to users and potentially devices, or is it a self-contained JWT refresh token)?
               3. Has it expired?
               4. Has it been revoked (e.g., due to user logging out everywhere, or suspected compromise)?
               5. Does it correspond to an active user (`deleted_at IS NULL`)?
               6. If the refresh token is invalid, expired, or revoked, return an authentication error (e.g., 401 Unauthorized or 403 Forbidden), and the client should treat the user as logged out. This might also trigger invalidation of other refresh tokens for that user if a strict security policy is in place.
         3. **Issue New JWT Access Token:**
            1. If the refresh token is valid, retrieve the associated [`users.id`](http://users.id).
            2. Generate a new JWT Access Token with updated `iat` and `exp` claims, and the same Hasura claims (`x-hasura-allowed-roles`, `x-hasura-default-role`, `x-hasura-user-id` derived from the user's current context – for now, assume basic user context).
            3. Sign the new access token.
         4. **(Optional but Recommended) Issue New Refresh Token (Refresh Token Rotation):**
            1. To enhance security, invalidate the used refresh token.
            2. Generate a _new_ refresh token with a new expiry.
            3. Store this new refresh token, replacing the old one.
            4. Send this new refresh token back to the client along with the new access token.
            5. _Note: The detailed strategy for refresh token rotation (e.g., grace periods for concurrent requests) should be outlined in `Core_Principle_AuthenticationSecurity.md`._
         5. **Return Tokens:**
            1. Send the new JWT Access Token (and new Refresh Token, if using rotation) back to the client.
      5. **3.4.5. Post-conditions / Outputs:**
         1. Client receives a new, valid JWT Access Token.
         2. (If using rotation) Client receives a new Refresh Token, and the old one is invalidated.
         3. The user's session is effectively extended without requiring re-authentication via credentials.
      6. **3.4.6. Error Handling / Exceptional Flows:**
         1. Invalid, expired, or revoked refresh token: Client should clear tokens and redirect to login.
         2. User account associated with refresh token is inactive or deleted
         3. Errors during token generation or storage.
      7. **3.4.7. Permissions / Authorization Notes:**
         1. The refresh token endpoint requires a valid refresh token for access.
   5. **3.5. Workflow: User Logout**

      1. **3.5.1. Trigger / Entry Point:**
         1. User clicks a "Logout" button/link in the application.
      2. **3.5.2. Pre-conditions / Required Inputs:**
         1. User is currently authenticated (client possesses a valid Access Token and potentially a Refresh Token).
         2. (Optional) Client sends the Refresh Token to the backend if server-side revocation is implemented.
      3. **3.5.3. User Interface Considerations (Functional):**
         1. Logout action should be clearly available.
         2. Confirmation prompt might be considered.
      4. **3.5.4. Step-by-Step Logic & Rules:**
         1. **Client-Side Token Invalidation:**
            1. The client application immediately deletes/clears its stored JWT Access Token.
               1. The client also deletes/clears its stored Refresh Token.
            2. **(Optional but Recommended) Server-Side Refresh Token Invalidation (Authentication Service):**
               1. Client makes a request to a logout endpoint on the Authentication Service (e.g., `/auth/logout`).
               2. If the client sends its refresh token, the Authentication Service should:
                  1. Validate the refresh token.
                  2. Mark this specific refresh token as revoked in its store, preventing it from being used to obtain new access tokens.
                  3. _Note: If a "logout everywhere" functionality is desired, all refresh tokens associated with the user would be revoked. This is a more advanced feature._ If the refresh token is not sent (e.g., it was stored in an HTTPOnly cookie that the client can't read directly but is sent with the request), the server can identify it from the request and revoke it.
            3. 3\. **Session Termination:** Any server-side session state associated with the tokens (if any, beyond the stateless nature of JWTs) should be cleared.
      5. **3.5.5. Post-conditions / Outputs:**
         1. Client-side tokens are cleared.
         2. (If implemented) Server-side refresh token is revoked.
         3. User is effectively logged out.
         4. **User Feedback (UI):** User is redirected to the login page or a public landing page.
      6. **3.5.6. Error Handling / Exceptional Flows:**
         1. Errors during server-side revocation (e.g., token already invalid). These usually don't prevent the client-side logout.
      7. **3.5.7. Permissions / Authorization Notes:**
         1. The logout endpoint (if it exists for server-side revocation) would require an authenticated state (e.g., a valid access token to identify the session, or the refresh token itself).

   6. ### **Workflow: Forgot Password / Password Reset**

      1. #### **Sub-Workflow: Request Password Reset**

         1. ##### **Trigger / Entry Point:**

            1. User clicks a "Forgot Password?" link, typically on the login page.
            2. User is presented with a form to enter their email address.
            3. User submits the email address.

         2. **3.6.1.2. Pre-conditions / Required Inputs (from User):**
            1. `email` (TEXT, NOT NULL, associated with an existing Hyper M v2 account).
         3. **3.6.1.3. User Interface Considerations (Functional):**
            1. Input field for email.
            2. Success message: "If an account exists for \[user_email\], a password reset link has been sent." (Generic message to prevent email enumeration).
            3. Error message for invalid email format.
         4. **3.6.1.4. Step-by-Step Logic & Rules:**
            1. **Client-Side Validation:** Basic check for email format.
            2. **Server-Side Submission:** User submits the email to a dedicated endpoint on the Authentication Service (e.g., `/auth/request-password-reset`).
            3. **Server-Side Input Validation:** Validate email format.
            4. **Check User Existence (Quietly):**
               1. Query `public.users` for a user with the provided `email` (normalized) and `deleted_at IS NULL` and `email_verified = TRUE`.
            5. **Generate Password Reset Token & Send Email (If User Exists & Verified):**
               1. **If a matching, verified user is found:**
                  1. Generate a secure, unique, time-limited password reset token associated with the user's ID.
                  2. Store this token temporarily (e.g., in a `password_reset_tokens` table with `user_id`, `token`, `expiry_datetime`).
                  3. Construct a password reset link (e.g., [`https://[app_domain]/reset-password?token=[reset_token`](https://[app_domain]/reset-password?token=[reset_token)`]`).
                  4. Send an email to the user's `email` address with this link and instructions.
            6. **Always Return Generic Success Response:**
               1. Regardless of whether a user was found or an email was sent, the API should return a generic success response to the client (e.g., HTTP 200 OK or 202 Accepted). This is crucial to prevent attackers from inferring which email addresses are registered in the system (email enumeration). The UI will display the generic message mentioned in 3.6.1.3.
         5. **3.6.1.5. Post-conditions / Outputs:**
            1. If a user existed, a password reset token is generated and stored, and an email is dispatched.
            2. **User Feedback (UI):** Generic message displayed, "If an account exists for \[user_email\], a password reset link has been sent."
         6. **3.6.1.6. Error Handling / Exceptional Flows:**
            1. Invalid email format (client/server validation).
            2. Failure to send email (email service down) \- ideally, log this error server-side. The user still sees the generic message.
         7. **3.6.1.7. Permissions / Authorization Notes:**
            1. This endpoint is publicly accessible.

      2. #### **Sub-Workflow: Reset Password**

         1. ##### **Trigger / Entry Point:**

            1. User clicks the password reset link received in their email (e.g., \`[https://\[app_domain\]/reset-password?token=\[reset_token](https://[app_domain]/reset-password?token=[reset_token)\]\`).
            2. User is presented with a form to enter their new password.
            3. User submits the new password.

         2. 3.6.2.2. Pre-conditions / Required Inputs:
            1. Valid, non-expired \`reset_token\` (as a URL query parameter).
            2. \`new_password\` (TEXT, NOT NULL, must meet complexity requirements).
            3. \`confirm_new_password\` (TEXT, NOT NULL, must match \`new_password\`).
         3. 3.6.2.3. User Interface Considerations (Functional):
            1. Password input fields for new password and confirmation.
            2. Display password complexity requirements.
            3. Success message: "Password successfully reset. You can now log in with your new password." with a link/button to the login page.
            4. Error messages for invalid/expired token, password mismatch, or password not meeting complexity.
         4. 3.6.2.4. Step-by-Step Logic & Rules:
            1. Frontend Token Retrieval:
               1. Frontend extracts the \`reset_token\` from the URL.
            2. Client-Side Validation:
               1. Validate new password for complexity and match.
            3. Server-Side Submission:
               1. User submits \`reset_token\`, \`new_password\`, and \`confirm_new_password\` to a dedicated backend endpoint (e.g., \`/auth/reset-password\`).
            4. Server-Side Input Validation:
               1. Validate \`new_password\` complexity.
               2. Verify \`new_password\` matches \`confirm_new_password\`.
            5. Token Validation (Authentication Service):
               1. Retrieve the \`reset_token\`.
               2. Check its validity:
                  1. Is it well-formed?
                  2. Does it exist in \`password_reset_tokens\` table?
                  3. Has it expired?
                  4. Does it correspond to an existing, active user?
                  5. If the token is invalid or expired, return an error (e.g., "Invalid or expired password reset link.").
            6. Password Hashing:
               1. Generate a strong cryptographic hash of the \`new_password\`.
            7. Update User Password:
               1. If the token is valid, retrieve the associated \`user_id\`.
               2. UPDATE the \`public.users\` record for this \`user_id\`:
                  1. Set \`password_hash\` to the new hash.
                  2. Set \`updated_at \= now()\`.
            8. Invalidate Password Reset Token:
               1. Delete or mark the \`reset_token\` record in \`password_reset_tokens\` as used to prevent reuse.
            9. (Optional but Recommended) Invalidate Active Sessions/Refresh Tokens:
               1. For enhanced security, consider invalidating all existing refresh tokens (and thereby active sessions) for this user, forcing them to log in again with the new password on all devices. This is a security measure against session hijacking if the account was compromised before the password reset. This logic would be part of the Authentication Service.
         5. 3.6.2.5. Post-conditions / Outputs:
            1. The user's \`password_hash\` in \`public.users\` is updated.
            2. The password reset token is invalidated.
            3. (Optional) Existing user sessions/refresh tokens are invalidated.
            4. User Feedback (UI):
               1. Display success message and direct user to login.
         6. Error Handling / Exceptional Flows:
            1. Token not found, invalid, or expired.
            2. Password complexity requirements not met.
            3. Passwords do not match.
            4. User account associated with token not found or inactive.
            5. Database error during user update.
         7. Permissions / Authorization Notes:
            1. This endpoint is publicly accessible (the token is the authorization mechanism).

   7. ### **Workflow: Initial Company Onboarding (Creating the First Company)**

      1. #### **Trigger / Entry Point:**

         1. A newly registered and email-verified user logs in for the first time and has no existing `company_memberships` where they are `active`.
         2. Alternatively, an existing user with no active company memberships navigates to a "Create Company" section.
         3. User is presented with a form to create their first company.

      2. #### **Pre-conditions / Required Inputs (from User):**

         1. User must be authenticated (valid JWT).
         2. `company_name` (TEXT, NOT NULL)
         3. `company_eik` (TEXT, NOT NULL, unique per country for legal entities \- initial validation might be basic format, deeper validation later)
         4. `company_country_id` (UUID, NOT NULL, FK to `public.countries`)
         5. `company_type_id` (UUID, NOT NULL, FK to `public.company_types`)
         6. `company_default_locale_id` (UUID, NOT NULL, FK to `public.locales`)
         7. `company_default_currency_id` (UUID, NOT NULL, FK to `public.currencies`) \- Must be a currency marked as usable for the selected `company_country_id`.
         8. (Optional but recommended) `company_address_line1`, `company_city` for the default company location.
         9. User's agreement to any company-specific terms if applicable (though usually covered by main ToS).

      3. **User Interface Considerations (Functional):**
         1. Multi-step form might be appropriate (e.g., Step 1: Company Details, Step 2: Default Location Details).
         2. Dropdowns for `company_country_id`, `company_type_id`, `company_default_locale_id`, `company_default_currency_id` (populated from respective lookup tables).
         3. Currency dropdown should ideally be filtered based on the selected country.
         4. Clear indication of required fields.
         5. Information about the automatic free trial initiation (e.g., "Your new company will start with a 30-day free trial of our Premium plan\!").
      4. **3.7.4. Step-by-Step Logic & Rules:**
         1. **Client-Side Validation:** Basic validation of required fields, EIK format (country-specific if possible).
         2. **Server-Side Submission:** User submits company creation data to a dedicated backend endpoint (e.g., Hasura Action/Connector, or specific endpoint in Foundation/Admin service). The authenticated `user_id` is available from the JWT.
         3. **Server-Side Input Validation:**
            1. Verify all required fields.
            2. Validate FKs (`company_country_id`, `company_type_id`, etc.) exist in their respective tables.
            3. Validate `company_eik` uniqueness within the selected `company_country_id` (if feasible at this stage, or marked for later admin verification for some jurisdictions). The DDL `companies.eik UNIQUE` enforces global uniqueness, which might be too strict if EIKs are only unique per country. We might need a composite unique index on `(eik, country_id)` or handle uniqueness validation more nuancedly. _Decision: The DDL has `eik TEXT NOT NULL UNIQUE`. This implies EIKs are globally unique in Hyper M v2. If this is not the case for real-world EIKs, the DDL needs revision. Assuming global uniqueness for now as per DDL._
            4. Validate `company_default_currency_id` is appropriate for the `company_country_id`.
         4. **Create `companies` Record:**
            1. INSERT a new record into `public.companies`:
            2. `id`: `gen_random_uuid()` (New Company ID)
            3. `name`: Provided `company_name`
            4. `eik`: Provided `company_eik`
            5. `country_id`: Provided `company_country_id`
            6. `company_type_id`: Provided `company_type_id`
            7. `default_locale_id`: Provided `company_default_locale_id`
            8. `default_currency_id`: Provided `company_default_currency_id`
            9. `is_vat_registered`: Default to `TRUE` or `FALSE` (configurable, or ask user? Let's assume default `TRUE` for now, can be changed later).
            10. `settings`: Initialize with empty JSONB `{}` or default settings. Store `saas_trial_ends_at = now() + interval '[ConfiguredTrialDurationDays] days'`.
            11. (Other fields like `legal_responsible_person`, `phone`, `vat` can be populated later through company settings UI).
         5. **Create Default `company_locations` Record:**
            1. INSERT a new record into `public.company_locations`:
            2. `id`: `gen_random_uuid()`
            3. `company_id`: The New Company ID created in step 4\.
            4. `name`: "Main Office" (or derived from `company_name`, or user input).
            5. `address_line1`, `city`, `post_code`, `region_name`: From user input if provided, otherwise can be minimal or prompted for later. Must satisfy NOT NULL constraints.
            6. `country_id`: Same as `companies.country_id`. `is_default`: `TRUE`.
         6. **Create `company_memberships` Record for Creator:**
            1. Retrieve the `admin` `role_id` from `public.roles` table (e.g., `SELECT id FROM public.roles WHERE value = 'admin'`).
            2. INSERT a new record into `public.company_memberships`:
            3. `user_id`: The `user_id` of the authenticated user creating the company.
            4. `company_id`: The New Company ID.
            5. `role_id`: The retrieved `admin` role ID.
            6. `status`: `'active'`. \* `invited_by_user_id`: `NULL` (as user created it themselves).
            7. `accepted_at`: `now()`.
         7. **Initiate SaaS Platform Trial Subscription (Conceptual \- Links to `BLA_Module_PlatformSubscriptionPlanManagement`):**  
            Logic (as detailed in the outline for the Platform Subscription BLA) is triggered to:
            1. Identify the default trial SaaS plan (e.g., "Premium Plan").
            2. Create a `company_saas_subscriptions` record for the new `company_id` with `status = 'trialing'`, `saas_plan_id` \= (trial plan ID), and `trial_ends_at` (e.g., 30 days from now).
            3. This step conceptually happens here; the full mechanics are in the other BLA.
         8. **Setup Default Document Sequences:**
            1. For the newly created default `company_locations.id`, create default entries in `document_sequence_definitions` for essential sequence types (e.g., 'FISCAL_DOCUMENTS', 'SALES_ORDERS', 'PURCHASE_ORDERS') with default start numbers, padding, etc. These can be configured later by the company admin.
      5. **3.7.5. Post-conditions / Outputs:**
         1. A new `companies` record exists.
         2. A default `company_locations` record linked to the new company exists and is marked as default.
         3. A `company_memberships` record exists, making the creator an active admin of the new company.
         4. The company is placed on a default SaaS free trial period (e.g., `company_saas_subscriptions` record created).
         5. Default document sequences are initialized.
         6. **User Feedback (UI):** Success message, e.g., "Company '\[Company Name\]' created successfully\! You are now ready to use Hyper M v2."
         7. **Redirection:** User is redirected to the dashboard of their newly created company. The client application should now send the `X-Hasura-Company-ID` (New Company ID) and the appropriate `X-Hasura-Role` ('admin') in headers for subsequent requests.
      6. **Error Handling / Exceptional Flows:**

         1. `company_eik` already exists (if global uniqueness is enforced and it's a true duplicate).
         2. Database errors during creation of any of the records.
         3. Failure to retrieve default 'admin' role.
         4. User trying to create a company when they already have an active company membership that restricts new company creation (policy decision).

      7. #### **Permissions / Authorization Notes:**

         1. Requires an authenticated user.
         2. System might have a policy on how many companies a single user can create (depending on the SaaS plan (except trial and free) though typically not restrictive for initial setup).

   8. ### **Workflow: Resend Email Verification Link**

      1. #### **Trigger / Entry Point:**

         1. User attempts to log in (Workflow 3.3) with an email address that exists but `users.email_verified` is `FALSE`. The login error message explicitly states the email needs verification and provides an option/link to resend the verification email.
         2. User clicks the "Resend Verification Email" link/button.
         3. (Alternatively, a user might navigate to a specific page if they realize they never received/lost the initial email, and input their email there).

      2. **3.8.2. Pre-conditions / Required Inputs (from User):**
         1. `email` (TEXT, NOT NULL, associated with an existing Hyper M v2 account that is not yet verified).
      3. **3.8.3. User Interface Considerations (Functional):**
         1. Typically, this is triggered from an error message on the login page.
         2. If it's a separate form, an input field for email.
         3. Success message: "A new verification email has been sent to \[user_email\]. Please check your inbox." (Generic to prevent confirming if an unverified account for that email actually exists, though at this point, if triggered from login error, we know it does).
         4. Error message if the email format is invalid.
      4. **3.8.4. Step-by-Step Logic & Rules:**
         1. **Client-Side Validation (if separate form):** Basic check for email format.
         2. **Server-Side Submission:** User's email is submitted to a dedicated endpoint on the Authentication Service (e.g., `/auth/resend-verification-email`).
         3. **Server-Side Input Validation:** Validate email format.
         4. **Retrieve User Record:**
            1. Query `public.users` table for a user with the provided `email` (normalized) and `deleted_at IS NULL`.
            2. If no user is found, return a generic success-like response or a subtle error that doesn't confirm/deny email existence if the entry point was not from a previous "unverified" error (to prevent enumeration). If triggered from a known "unverified" state, a more direct error like "User not found" could be acceptable if the email was mistyped on resend.
         5. **Check Email Verification Status:**
            1. If the user is found, check `users.email_verified`.
            2. If `email_verified` is `TRUE`, return a message like "This email address has already been verified. You can proceed to login."
            3. If `email_verified` is `FALSE`: Proceed to generate and send a new token.
         6. **Generate Email Verification Token (Same as in Registration Workflow 3.1.4.7):**
            1. Generate a _new_ secure, unique, time-limited token associated with the user's ID and email.
            2. Any previously generated (but unused) verification tokens for this user should ideally be invalidated or the new token should supersede them.
            3. Store this new token (e.g., in `email_verification_tokens`, potentially replacing an old one for that user).
         7. **Send Verification Email (Same as in Registration Workflow 3.1.4.8):**
            1. Construct a new email verification link containing the new token.
            2. Send the email to the user's `email` address.
      5. **3.8.5. Post-conditions / Outputs:**
         1. A new verification email has been dispatched to the user.
         2. A new verification token has been generated and stored (or an existing one updated/replaced).
         3. **User Feedback (UI):** Display a success message, e.g., "A new verification link has been sent to \[user_email\]. Please check your inbox."
      6. **3.8.6. Error Handling / Exceptional Flows:**

         1. Email format invalid.
         2. Email address already verified.
         3. Email address not found in the system (handle with generic message if entry point is public).
         4. Failure to send verification email (email service down).

      7. #### **Permissions / Authorization Notes:**

         1. This endpoint is publicly accessible.

3. **4\. Specific Calculations & Algorithms (If Applicable)**

   1. **4.1. Password Hashing Algorithm:**
      1. **Algorithm:** Industry-standard strong hashing algorithm (e.g., bcrypt with a configurable cost factor, or Argon2).
      2. **Purpose:** To securely store user passwords, ensuring that plain-text passwords are never stored.
      3. **Note:** The specific algorithm and its parameters should be documented in a central security policy document (e.g., `Core_Principle_AuthenticationSecurity.md`). This BLA notes its use.
   2. **4.2. Secure Token Generation:**

      1. **Method:** Cryptographically secure pseudo-random number generator (CSPRNG) for generating verification tokens, password reset tokens, and refresh tokens (if not using JWTs for all).
      2. **Length & Complexity:** Tokens should be sufficiently long and complex to prevent guessing.
      3. **Uniqueness:** Ensure generated tokens are unique within their scope and timeframe.
      4. **Time-Limitation:** All stateful tokens (email verification, password reset) must have a defined, reasonably short expiry period. JWTs (access & refresh) have `exp` claims.
      5. **Note:** Specifics also to be detailed in `Core_Principle_AuthenticationSecurity.md`.

         _(For this BLA, there aren't many other complex calculations beyond standard cryptographic operations which are more principles of secure implementation than unique business algorithms.)_

4. **5\. Integration Points**
   1. **5.1. Internal Hyper M v2 Modules:**
      1. **Database (`public` schema):** Direct interaction with `users`, `companies`, `company_memberships`, `company_locations`, `roles`, and potentially token storage tables (`email_verification_tokens`, `password_reset_tokens`).
      2. **Document Numbering Module:** For initializing default `document_sequence_definitions` upon new company creation.
      3. **Platform Subscription & Plan Management Module (Conceptual):** The "Initial Company Onboarding" workflow triggers the initiation of a SaaS trial subscription, managed by this future module.
   2. **5.2. External Services:**
      1. **Authentication Service (Dedicated Node.js Service):** This external service is responsible for:
         1. Handling all authentication-related endpoints (/register, /login, /refresh-token, /request-password-reset, /reset-password, /verify-email, /resend-verification-email, /logout).
         2. Managing password hashing and comparison.
         3. Issuing and validating JWTs (Access & potentially Refresh tokens).
         4. Managing secure token generation and storage/validation for email verification and password resets.
         5. Communicating with the PostgreSQL database.
      2. **Email Service (e.g., SendGrid, AWS SES, Mailgun):**
         1. Used to send transactional emails:
         2. Email verification links.
         3. Password reset links.
         4. Welcome emails (optional, upon successful registration/onboarding).
   3. **Hasura GraphQL Engine:**
      1. The Authentication Service generates JWTs that are consumed and validated by Hasura to control data access based on `x-hasura-*` claims.
5. **6\. Data Integrity & Constraints (Beyond DDL)**
   1. **6.1. User-Company Linkage:** A new company creation (Workflow 3.7) must atomically create the `companies` record, the default `company_locations` record, and the `company_memberships` record linking the creating user as an 'admin' with 'active' status. Failure in any part should roll back the entire operation. (This is typically handled by database transactions managed by the Authentication Service logic).
   2. **6.2. Role Existence:** The 'admin' role (identified by `roles.value = 'admin'`) must exist in the `public.roles` table before a user can be assigned this role during company creation. System seeding of default roles is implied.
   3. **6.3. Default Settings Propagation:** Upon new company creation, appropriate default settings (e.g., initializing `document_sequence_definitions`, setting up the SaaS trial in `company_saas_subscriptions`) must be applied consistently.
   4. **6.4. Token Uniqueness and Expiry:** Application logic within the Authentication Service must enforce the uniqueness (where appropriate) and expiry of verification and reset tokens. Used tokens must be invalidated to prevent replay attacks.
6. **7\. Reporting Considerations (High-Level)**
   1. **User Registrations:** Number of new user sign-ups over time.
   2. **Email Verification Rates:** Percentage of registered users who verify their email.
   3. **Company Creation Rates:** Number of new companies created over time.
   4. **Login Activity:** Number of active users, frequency of logins (though more relevant for overall system monitoring).
   5. **Trial Initiations:** Number of SaaS trials started. _(These are primarily operational metrics for Hyper M v2 platform administrators rather than for tenant companies at this stage.)_
7. **8\. Open Questions / Future Considerations for this BLA**
   1. **Password Complexity Rules:** Specific rules (min length, character types, not matching email, etc.) to be finalized and documented in `Core_Principle_AuthenticationSecurity.md`.
   2. **Account Lockout Policy:** Strategy for handling multiple failed login attempts (e.g., temporary lockout, CAPTCHA). (Future enhancement).
   3. **"Remember Me" Functionality:** If implementing, details on how long-lived sessions or refresh tokens are managed for this.
   4. **Social Logins (Google, etc.):** Deferred for now, but would require significant additions to this BLA if implemented.
   5. **Two-Factor Authentication (2FA):** Deferred for now, a significant security enhancement.
   6. **User Profile Management:** Workflows for users to update their `first_name`, `last_name`, change password (when logged in), manage their own profile details. (This might be a separate, subsequent BLA or part of a "User Settings" BLA).
   7. **"Magic Link" Logins:** Passwordless login option. (Future enhancement).
   8. **Detailed Refresh Token Revocation Strategy:** E.g., handling "logout everywhere," detecting compromised refresh tokens. Details in `Core_Principle_AuthenticationSecurity.md`.
   9. **Global Uniqueness of `companies.eik`:** Confirm if this DDL constraint aligns with real-world requirements for EIKs across different countries. If EIKs are only unique _within_ a country, the DDL `UNIQUE` constraint on `eik` needs to be changed to `UNIQUE (eik, country_id)`. The current BLA assumes global uniqueness as per the provided DDL.
