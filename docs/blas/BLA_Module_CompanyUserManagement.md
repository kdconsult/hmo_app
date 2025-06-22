**Business Logic Addendum: Company & User Management**

**Document Version:** 1.0 **Date:** 16.06.2025  
**Related DDLs:** `public.companies`, `public.company_locations`, `public.company_types`, `public.company_memberships`, `public.company_membership_status_enum`, `public.users`, `public.roles`, `public.countries`, `public.locales`, `public.currencies`, `public.document_sequence_definitions`.  
**Primary Audience:** Development Team

1. **Overview & Purpose**

- This BLA defines the business logic for managing core company settings, company operational locations, inviting users to a company, and managing user memberships (roles and statuses) within a specific company. It also covers the management of document numbering sequences associated with company locations.
- Key goals include:
  - Allowing company administrators to configure their company details and operational structure.
  - Providing a secure and clear process for adding and managing user access to a company.
  - Ensuring proper role-based access control within the company context.
  - Enabling the setup and customization of document numbering for various business documents.

---

2. **Core Entities & Their States/Statuses**

- **`companies`:**

  - Purpose: Represents a tenant organization. This BLA focuses on _managing an existing_ company's details.
  - Key fields for this BLA: All fields can be managed post-creation, e.g., `name`, `legal_responsible_person`, `phone`, `email`, `vat`, `eik`, `company_type_id`, `uses_supto`, `country_id`, `default_locale_id`, `default_currency_id`, `settings` (for various company-specific configurations), `is_vat_registered`.
  - Status Lifecycle: Primarily managed via `deleted_at` for soft deletion. Active companies are those where `deleted_at IS NULL`.
  - **Translations (`company_translations`):** Management of translated company fields (`name`, `legal_responsible_person`).

- **`company_locations`:**

  - Purpose: Represents an operational site for a company. This BLA covers creating additional locations and managing existing ones.
  - Key fields for this BLA: All fields. `is_default` logic ensures only one default location per company.
  - Status Lifecycle: Primarily managed via `deleted_at` for soft deletion.
  - **Translations (`company_location_translations`):** Management of translated location fields (`name`, address components).

- **`company_memberships`:**

  - Purpose: Links a `user` to a `company` with a specific `role` and `status`. This is central to this BLA.
  - Key fields for this BLA: `user_id`, `company_id`, `role_id`, `status`, `notes`.
  - Status Lifecycle for `status` (`company_membership_status_enum`):
    - `pending`: Invitation sent to a user, awaiting their acceptance.
    - `active`: User is an active member with assigned role permissions.
    - `inactive`: User's membership is temporarily suspended by an admin (e.g., user on leave). They cannot access the company but their record remains.
    - `removed`: User has been permanently removed by an admin. They can no longer access the company. Record kept for history/audit. (Transition to this state sets `deleted_at`).
    - _Transitions:_
      - (New Invite) \-\> `pending`
      - `pending` \-\> `active` (on user acceptance)
      - `active` \-\> `inactive` (by admin action)
      - `inactive` \-\> `active` (by admin action)
      - `active` or `inactive` \-\> `removed` (by admin action, irreversible to previous states via UI, but `deleted_at` could theoretically be cleared by a super admin).

- **`users`:**

  - Purpose: Global user identity. This BLA interacts with it primarily by searching for existing users to invite.
  - Key fields for this BLA: `email` (for searching/inviting), `id`.

- **`roles`:**

  - Purpose: Defines the permission sets available within a company (e.g., 'admin', 'manager', 'sales_rep').
  - Key fields for this BLA: `id`, `value`, `description`. This BLA assumes roles are pre-defined; it doesn't cover creating new role types themselves, but assigning existing ones.

- **`document_sequence_definitions`:**
  - Purpose: Defines document numbering sequences scoped by `company_location_id`.
  - Key fields for this BLA: All fields. Admins can create new sequences for specific locations/types or modify existing ones (e.g., change prefix, current_number if no documents yet issued from it or after a reset).
  - Status Lifecycle: `is_active` (BOOLEAN) to enable/disable a sequence.

3. ### **Key Workflows & Processes**

   1. #### **Workflow: Manage Company Profile & Core Settings**

      1. ##### **Trigger / Entry Point:**

         - An authenticated user with 'admin' role for the currently selected company navigates to the "Company Settings" or "Company Profile" section in the application.

      2. **Pre-conditions / Required Inputs:**
         - User must be authenticated and have an 'admin' role within the active `X-Hasura-Company-ID`.
         - The system loads the current details of the active `company`.
      3. **User Interface Considerations (Functional):**
         - A form displaying current company details, with fields editable by the admin.
         - Fields would include: `name`, `legal_responsible_person`, `phone`, `email`, `vat`, `eik`, `company_type_id`, `uses_supto`, `country_id`, `default_locale_id`, `default_currency_id`, `is_vat_registered`.
         - Section for managing `companies.settings` JSONB (e.g., specific flags or configurations relevant to the company's operation within Hyper M v2, excluding SaaS plan settings which are managed elsewhere).
         - Separate interface for managing `company_translations` for defined translatable fields.
         - Save/Cancel buttons.
      4. **Step-by-Step Logic & Rules:**
         - **Load Data:** Fetch and display current data for the `companies.id` matching `X-Hasura-Company-ID`.
         - **User Edits:** User modifies editable fields.
         - **Client-Side Validation:** Standard field validations (e.g., required, format for email/phone, EIK format).
         - **Server-Side Submission:** User submits updated company data.
         - **Server-Side Input Validation:**
           - Re-validate all submitted fields.
           - Validate FKs (`company_type_id`, `country_id`, `default_locale_id`, `default_currency_id`).
           - **EIK Uniqueness:** If `eik` or `country_id` is changed, re-validate EIK uniqueness (globally or per country, as per final DDL decision for `companies.eik` constraint).
           - **VAT Number Validation (Optional but Recommended):** If `vat` is provided/changed and `is_vat_registered` is true, attempt to validate its format. For EU VAT numbers, an optional asynchronous VIES check could be triggered (logging result in `vat_responses`), but invoice-time VIES checks are more critical.
           - **Default Currency Change:** If `default_currency_id` is changed, consider implications. Existing financial documents are in their original currencies and company default conversions. This change primarily affects _new_ default currency conversions and company-level reporting defaults going forward. _Business Rule: Changing default currency does not retroactively change historical document conversions._
         - **Update `companies` Record:**
           - UPDATE the `public.companies` record for the given `company_id` with the validated new values.
           - Set `updated_at = now()`.
         - **Manage `company_translations` (If UI supports it directly):**
           - If translations were edited, INSERT or UPDATE records in `public.company_translations` for the relevant `locale_id`.
      5. **Post-conditions / Outputs:**
         - The `public.companies` record is updated.
         - Associated `company_translations` may be updated.
         - **User Feedback (UI):** Success message, e.g., "Company settings updated successfully."
      6. **Error Handling / Exceptional Flows:**

         - Validation errors (e.g., EIK duplicate, invalid FK).
         - Concurrency issues (another admin edited simultaneously \- optimistic locking might be a future consideration).
         - Database errors.

      7. ##### **Permissions / Authorization Notes:**

         - Requires 'admin' role for the active company.

   2. #### **Workflow: Manage Company Locations**

      1. ##### **Sub-Workflow: Create New Company Location**

         - **Trigger:** Admin navigates to "Company Locations" section and clicks "Add New Location."
         - **Required Inputs:** `name`, `address_line1`, `city`, `country_id` (defaults to company's country but can be different if company operates cross-border locations), `phone` (optional), `email` (optional), etc.
         - **Logic:**
           - Validate inputs. Ensure `name` is unique per `company_id` (as per `company_locations_company_name_unique` constraint).
           - INSERT new record into `public.company_locations` linked to the active `company_id`.
           - `is_default` will be `FALSE` (unless it's the very first location being created after the initial default, and the admin explicitly sets it and changes the old default – complex UI). Typically, only one can be default.
           - **Crucial:** Prompt admin if they want to set up `document_sequence_definitions` for this new location immediately or guide them to that section.
         - **Post-conditions:** New `company_locations` record created
         - **Permissions:** 'admin' role for the active company.  


      2. **Sub-Workflow: Edit Existing Company Location**

         - **Trigger:** Admin selects a location to edit.
         - **Logic:**
           - Load location data.
           - User edits fields.
           - Validate inputs (especially `name` uniqueness if changed).
           - Handle `is_default` change: If this location is set to default, ensure any other location for the company has `is_default` set to `FALSE` (enforced by `company_locations_single_default_per_company` unique index via application logic before update).
           - UPDATE `public.company_locations` record.
           - Manage `company_location_translations` if applicable.
         - **Permissions:** 'admin' role for the active company.

      3. ##### **Sub-Workflow: Delete Company Location (Soft Delete)**

         - **Trigger:** Admin selects a location to delete.
         - **Logic:**
           - **Pre-deletion Checks:**
             - Verify the location is not marked as `is_default` (a default location cannot be deleted until another is set as default).
             - Check if there are dependent active entities tied _exclusively_ to this location that would prevent deletion (e.g., active `document_sequence_definitions` that are not shared, `inventory_stock_items` physically in storages only at this location, open `sales_orders` tied to this location). The policy for this needs definition (e.g., prevent deletion, or allow archiving with consequences). For now, assume a simpler check: cannot delete if it's default or has active document sequences.
           - If checks pass, UPDATE `public.company_locations` record: Set `deleted_at = now()`.
           - (Optional) Deactivate associated `document_sequence_definitions` or prompt admin.
         - **Permissions:** 'admin' role for the active company.

   3. #### **Workflow: Invite New User to Company**

      1. ##### **Trigger / Entry Point:**

         - An authenticated user with 'admin' role (or a role with specific 'manage_users' permission) for the currently selected company navigates to the "User Management" or "Team Members" section.
         - Admin clicks "Invite New User" or similar action.

      2. **Pre-conditions / Required Inputs (from Admin):**
         - `email` (TEXT, NOT NULL, of the user to be invited).
         - `role_id` (UUID, NOT NULL, FK to `public.roles` \- the role the invited user will have in this company).
         - (Optional) `first_name`, `last_name` (if inviting a brand new user to Hyper M v2 itself).
         - (Optional) Custom invitation message.
      3. **User Interface Considerations (Functional):**
         - Form to input email and select a role from a dropdown (populated from `public.roles`).
         - Indication if the email already corresponds to an existing Hyper M v2 global user.
         - If inviting a new global user, fields for first/last name might appear.
      4. **Step-by-Step Logic & Rules:**
         - **Admin provides email and selects role.**
         - **Client-Side Validation:** Validate email format.
         - **Server-Side Submission:** Data submitted to backend (e.g., Hasura Action/Connector). Authenticated admin's `user_id` (inviter) and active `company_id` are known.
         - **Server-Side Input Validation:**
           - Verify `email` and `role_id` are provided and valid.
           - Check if `role_id` exists in `public.roles`.
           - **SaaS Plan Check (Feature Gating):** Check if the company's current SaaS plan allows adding more users or users with this specific role. If limit reached, return an error (e.g., "User limit for your current plan reached. Please upgrade."). Refer to `BLA_Module_PlatformSubscriptionPlanManagement`.
         - **Check if Invited User Already Has Membership:**
           - Query `public.company_memberships` to see if a record already exists for the given `email` (resolved to `user_id`) and the current `company_id` where `status` is 'active', 'pending', or 'inactive'.
           - If an active/pending/inactive membership already exists, inform the admin (e.g., "This user is already a member or has a pending invitation to this company.").
         - **Identify Target User (Invitee):**
           - Query `public.users` to find if a global user exists with the provided `invitee_email`.
           - **Scenario A: Invitee is an Existing Hyper M v2 User:**
             - Retrieve their `users.id` (Invitee User ID).
           - **Scenario B: Invitee is NOT an Existing Hyper M v2 User:**
             - Admin must provide `first_name` and `last_name` for the new user.
             - Create a new global user record in `public.users` (as per simplified registration flow \- no password set by admin, `email_verified = FALSE` initially).
             - `id`: `gen_random_uuid()` (New Invitee User ID)
             - `email`: `invitee_email`
             - `first_name`, `last_name`: Provided by admin.
             - `password_hash`: Set to a non-loginable state or `NULL` (user will set password via invitation acceptance flow).
             - `email_verified`: `FALSE`.
             - _Note: This new user will need to complete a form of account activation / password setting when they accept the invitation._
         - **Create `company_memberships` Record:**
           - INSERT a new record into `public.company_memberships`:
             - `user_id`: Invitee User ID (either existing or newly created).
             - `company_id`: Current active `company_id`.
             - `role_id`: Provided `role_id`.
             - `status`: `'pending'`.
             - `invited_by_user_id`: `user_id` of the inviting admin.
             - `invited_at`: `now()`.
         - **Send Invitation Email:**
           - Generate a unique, time-limited invitation acceptance token. Store it (e.g., in `company_membership_invitation_tokens` with `membership_id`, `token`, `expiry`).
           - Construct an invitation link (e.g., [`https://[app_domain]/accept-invitation?token=[invitation_token`](https://[app_domain]/accept-invitation?token=[invitation_token)`]`).
           - Send an email via the Email Service to `invitee_email`:
             - If invitee was new to Hyper M: Email should explain they've been invited to company X, need to activate their Hyper M account (set password), and accept the company invitation.
             - If invitee was an existing Hyper M user: Email should explain they've been invited to company X and provide the link to accept.
      5. **Post-conditions / Outputs:**
         - If invitee was new, a `users` record is created for them (pending password set/activation).
         - A `company_memberships` record is created with `status = 'pending'`.
         - An invitation email is dispatched.
         - **User Feedback (UI for Admin):** "Invitation sent successfully to \[invitee_email\]."
      6. **Error Handling / Exceptional Flows:**

         - User limit reached based on SaaS plan.
         - Invited user already has an active/pending membership.
         - Role ID invalid.
         - Failure to send email.
         - Database errors.

      7. ##### **Permissions / Authorization Notes:**

         - Requires 'admin' role or specific 'manage_users_in_company' permission for the active company.

   4. #### **Workflow: Invited User Accepts Company Invitation**

      1. ##### **Trigger / Entry Point:**

         - Invited user clicks the invitation acceptance link from their email (e.g., [`https://[app_domain]/accept-invitation?token=[invitation_token`](https://[app_domain]/accept-invitation?token=[invitation_token)`]`).

      2. **Pre-conditions / Required Inputs:**
         - Valid, non-expired `invitation_token`.
      3. **User Interface Considerations (Functional):**
         - Page displays details of the invitation (Company Name, Inviting User \- optional, Role offered).
         - **If Invitee was NEW to Hyper M v2 and needs to set password:** Form to set and confirm their new password.
         - Buttons: "Accept Invitation" / "Decline Invitation".
      4. **Step-by-Step Logic & Rules:**
         - **Backend Request:** Frontend sends `invitation_token` to backend (Authentication/Membership Service).
         - **Token Validation:**
           - Validate token: exists, not expired, linked to a `company_memberships` record with `status = 'pending'`.
           - If invalid/expired, display error: "Invalid or expired invitation."
         - **Identify User and Membership:** Retrieve `user_id` and `company_memberships.id` from the token. Let `user_record` be the user from `public.users`.
         - **If User Needs to Set Password (New Hyper M v2 User Flow):**
           - User submits `new_password` and `confirm_new_password`.
           - Validate passwords (complexity, match).
           - Hash `new_password`.
           - UPDATE `public.users` SET `password_hash` \= (new hash), `email_verified = TRUE` (as clicking email link implies email ownership), `updated_at = now()` WHERE `id` \= `user_record.id`.
         - **User Action (Accept/Decline):**
           - **If User Accepts:**
             - UPDATE `public.company_memberships` SET `status = 'active'`, `accepted_at = now()`, `updated_at = now()` WHERE `id` \= (membership_id from token).
             - Invalidate the invitation token.
             - (Optional) Send notification to inviting admin that invitation was accepted.
             - Log the user in (issue JWT) if they just set their password or if they weren't already logged in. Redirect to the company dashboard.
           - **If User Declines:**
             - UPDATE `public.company_memberships` SET `status = 'removed'` (or a new ENUM value like `'declined'`), `notes = 'Invitation declined by user'`, `updated_at = now()` WHERE `id` \= (membership_id from token).
             - Invalidate the invitation token.
             - (Optional) Send notification to inviting admin.
             - Display a confirmation message. User is not logged into that company.
      5. **Post-conditions / Outputs:**
         - `company_memberships.status` is updated to `'active'` or `'removed'/'declined'`.
         - If accepted by a new user, their `users` record is fully activated (`password_hash` set, `email_verified = TRUE`).
         - Invitation token is invalidated.
         - **User Feedback (UI):** Appropriate success/confirmation message. Redirection if accepted and logged in.
      6. **Error Handling / Exceptional Flows:**

         - Invalid/expired token.
         - Password validation errors (for new users).
         - Database errors.

      7. ##### **Permissions / Authorization Notes:**

         - Publicly accessible endpoint (token is authorization). User might need to be logged into their global Hyper M account if they are an existing user.

   5. #### **Workflow: Manage Existing Company Membership (by Admin)**

      1. ##### **Trigger / Entry Point:**

         - An authenticated user with 'admin' role (or appropriate 'manage_users_in_company' permission) for the currently selected company navigates to the "User Management" or "Team Members" section.
         - Admin selects an existing member from the list to manage.

      2. **Pre-conditions / Required Inputs:**
         - Admin is authenticated for the active `X-Hasura-Company-ID`.
         - `company_membership_id` of the member being managed.
      3. **User Interface Considerations (Functional):**
         - Display current membership details: User's name, email, current role, current status.
         - Options to:
           - Change Role (Dropdown of available `public.roles`).
           - Change Status (Dropdown/buttons for 'active', 'inactive', 'removed').
           - Resend Invitation (if status is 'pending').
           - Add/Edit notes related to the membership.
      4. **Step-by-Step Logic & Rules:**
         - **Change User's Role in Company:**
           - Admin selects a new \`role_id\` for the user.
           - **SaaS Plan Check (Feature Gating):** If changing to a role has implications for user counts or role types restricted by the SaaS plan, perform a check. (e.g., "Cannot assign 'Admin' role as your plan limit for admins is reached."). Refer to \`BLA_Module_PlatformSubscriptionPlanManagement\`.
           - UPDATE \`public.company_memberships\` SET \`role_id\` \= (new selected \`role_id\`), \`updated_at \= now()\` WHERE \`id\` \= \`company_membership_id\`.
           - (Optional) Notify the user of their role change.
           - **User Feedback (UI for Admin):** "User's role updated successfully."
         - **Change User's Membership Status (Active \<-\> Inactive):**
           - Admin selects new status: `'active'` or `'inactive'`.
           - UPDATE `public.company_memberships` SET `status` \= (new selected status), `updated_at = now()` WHERE `id` \= `company_membership_id`.
           - If status changed to `'inactive'`, any active sessions for that user _within this specific company context_ should ideally be prompted for re-evaluation by Hasura (e.g., if Hasura supports dynamic claim updates or if client needs to re-fetch claims upon next action). The user's JWT itself doesn't change, but RLS for that company should now block access.
           - (Optional) Notify the user of their status change.
           - **User Feedback (UI for Admin):** "User's status updated successfully."
         - **Remove User from Company (Set status to 'removed'):**
           - Admin chooses to "Remove" the user. A confirmation prompt is highly recommended ("Are you sure you want to remove \[User Name\] from \[Company Name\]? This action is irreversible.").
           - Upon confirmation:
             - UPDATE `public.company_memberships` SET `status = 'removed'`, `deleted_at = now()`, `notes = (Admin's reason if provided)`, `updated_at = now()` WHERE `id` \= `company_membership_id`.
             - **Important:** This does NOT delete the global `public.users` record. It only revokes their access to _this specific company_.
             - Any active sessions for that user _within this specific company context_ should be invalidated/re-evaluated by Hasura.
             - (Optional) Notify the user they have been removed from the company.
             - (Optional) Reassign any critical items owned by this user within the company (e.g., if they were the sole owner of certain documents – this is more advanced business process logic).
           - **User Feedback (UI for Admin):** "User removed successfully from the company."
           - _Business Rule:_ Admin cannot remove themselves if they are the sole 'admin' with 'active' status in the company, unless specific "company deletion/transfer ownership" workflows are in place (which are outside this BLA's scope).
         - **Resend Invitation (if membership status is 'pending'):**
           - Admin clicks "Resend Invitation" for a user whose `company_memberships.status` is `'pending'`.
           - Logic follows Workflow 3.3 ("Invite New User to Company"), specifically steps 3.3.4.8 (Generate new token, Send email). The existing `company_memberships` record is used.
           - Previous invitation token for this specific membership should be invalidated.
           - **User Feedback (UI for Admin):** "New invitation sent successfully."
         - **Add/Edit Membership Notes:**
           - Admin adds or modifies text in the `company_memberships.notes` field.
           - UPDATE `public.company_memberships` SET `notes = (new notes)`, `updated_at = now()` WHERE `id` \= `company_membership_id`.
           - **User Feedback (UI for Admin):** "Notes updated."
      5. **Post-conditions / Outputs:**
         - The `public.company_memberships` record is updated according to the action taken (role, status, notes, or `deleted_at`).
         - Relevant notifications may be sent.
      6. **Error Handling / Exceptional Flows:**

         - Trying to remove the last active admin.
         - SaaS plan limits preventing role change.
         - User/membership not found.
         - Database errors.

      7. ##### **Permissions / Authorization Notes:**

         - Requires 'admin' role or specific 'manage_users_in_company' permission for the active company.
         - An admin cannot typically change their own role to a non-admin role if they are the sole admin, nor remove themselves if sole admin.

   6. #### **Workflow: Manage Document Numbering Sequences**

      1. ##### **Trigger / Entry Point:**

         - An authenticated user with 'admin' role for the currently selected company navigates to a "Document Numbering Settings" or "Sequence Definitions" section, typically associated with a specific `company_location`.

      2. **Pre-conditions / Required Inputs:**
         - Admin is authenticated for the active `X-Hasura-Company-ID`.
         - Admin has selected or is in the context of a specific `company_location_id` for which sequences are being managed.
      3. **User Interface Considerations (Functional):**
         - List of existing `document_sequence_definitions` for the selected `company_location_id`.
         - Ability to "Add New Sequence Definition" or "Edit" an existing one.
         - Form fields for a sequence definition:
           - `sequence_type_key` (TEXT, e.g., 'FISCAL_DOCUMENTS', 'SALES_ORDERS', 'PURCHASE_ORDERS', 'GOODS_RECEIPT_NOTES', 'PROFORMA_INVOICES', 'DELIVERY_NOTES'). This might be a dropdown of predefined system types or allow custom keys for certain internal documents.
           - `prefix` (TEXT, Optional)
           - `suffix` (TEXT, Optional, e.g., "/{YYYY}")
           - `start_number` (BIGINT, Default 1\)
           - `current_number` (BIGINT, Default based on `start_number` and `increment_by`). _Editable only under specific conditions (e.g., if no documents have been issued from this sequence yet, or after a manual reset)._
           - `increment_by` (INTEGER, Default 1, Must be \> 0\)
           - `padding_length` (INTEGER, Default 0, e.g., 10 for "0000000001")
           - `allow_periodic_reset` (BOOLEAN, Default FALSE)
           - `last_reset_date` (DATE, Read-only or system-set during reset operation).
           - `is_active` (BOOLEAN, Default TRUE).
      4. **Step-by-Step Logic & Rules:**
         - **View Existing Sequence Definitions:**
           - System fetches and displays all `document_sequence_definitions` where `company_location_id` matches the selected location.
         - **Add New Sequence Definition:**
           - Admin provides all required fields for a new sequence.
           - **Client-Side Validation:** Check data types, `increment_by > 0`, `padding_length >= 0`.
           - **Server-Side Submission.**
           - **Server-Side Input Validation:**
             - Re-validate inputs.
             - Ensure `sequence_type_key` is unique for the given `company_location_id` (enforced by DDL constraint `document_sequence_definitions_location_type_key`).
             - Set `current_number`: If `start_number` is N and `increment_by` is I, `current_number` should be initialized to `N - I` so the first number generated will be N. (The `get_next_document_number` function expects `current_number` to be the _last used_ number).
           - INSERT new record into `public.document_sequence_definitions`.
           - **User Feedback (UI for Admin):** "New document sequence created successfully."
         - **Edit Existing Sequence Definition:**
           - Admin selects a sequence to edit. System loads its current data.
           - Admin modifies editable fields.
           - **Business Rules for Editing:**
             - `company_location_id` and `sequence_type_key` (the composite key) should generally not be editable as this defines the sequence. If a change is needed, it's often better to deactivate the old and create a new one.
             - `start_number`: Can be changed. If `start_number` is increased above `current_number`, the `get_next_document_number` function will jump to the new `start_number`.
             - `current_number`:
               - **Critical:** This field should be edited with extreme caution and typically only by advanced users or system administrators if correcting an issue.
               - It should ideally _not_ be editable if documents have already been issued using this sequence for the current period (if `allow_periodic_reset=TRUE`). Changing it arbitrarily can lead to duplicate document numbers or gaps.
               - If `allow_periodic_reset=TRUE` and a reset is due (e.g., new year), the system (via `get_next_document_number` or a manual reset process) would update `current_number` back to `start_number - increment_by` and set `last_reset_date`.
             - `prefix`, `suffix`, `increment_by`, `padding_length`, `allow_periodic_reset`, `is_active` can generally be modified. Changing `padding_length` or `increment_by` for an active sequence needs careful consideration.
           - **Server-Side Submission & Validation.**
           - UPDATE `public.document_sequence_definitions` record.
           - **User Feedback (UI for Admin):** "Document sequence updated successfully."
         - **Deactivate/Activate Sequence Definition:**
           - Admin toggles the `is_active` flag.
           - UPDATE `public.document_sequence_definitions` SET `is_active` \= (new value).
           - **Note:** The `get_next_document_number()` function will only use sequences where `is_active = TRUE`.
         - **(Conceptual) Manual Periodic Reset (If `allow_periodic_reset` is TRUE):**
           - _This might be a separate admin action rather than a direct edit of `current_number`._
           - Trigger: Admin initiates a "Reset Sequence for New Period" for a sequence type that allows it (e.g., at the start of a new year).
           - Logic:
             - Verify `allow_periodic_reset` is TRUE.
             - Confirm with admin.
             - UPDATE `public.document_sequence_definitions`:
               - Set `current_number = start_number - increment_by`.
               - Set `last_reset_date = CURRENT_DATE` (or start of the period).
             - Log this administrative action.
           - **User Feedback (UI for Admin):** "Sequence reset successfully for the new period."
           - _The `get_next_document_number()` function also contains logic for automatic reset if a new period is detected based on `last_reset_date` and `allow_periodic_reset`._
      5. **Post-conditions / Outputs:**
         - `public.document_sequence_definitions` records are created, updated, or their `is_active` status changed.
      6. **Error Handling / Exceptional Flows:**

         - Attempting to create a duplicate `(company_location_id, sequence_type_key)`.
         - Invalid input values.
         - Attempting to edit `current_number` inappropriately for an active, in-use sequence.

      7. ##### **Permissions / Authorization Notes:**

         - Requires 'admin' role for the active company.

4. ### **Specific Calculations & Algorithms (If Applicable)**

   1. #### **Document Number Generation Logic:**

      1. While the `get_next_document_number(p_company_location_id UUID, p_sequence_type_key TEXT)` PostgreSQL function (defined in DDLs) handles the core atomic increment, padding, prefix/suffix application, and periodic reset, the _administration_ of its defining parameters (`start_number`, `current_number`, `padding_length`, etc.) is managed via workflows in this BLA.
      2. The algorithm for initializing `current_number` for a new sequence is: `current_number = start_number - increment_by`.
      3. The algorithm for a periodic reset (manual or automatic within the function) sets `current_number = start_number - increment_by` and updates `last_reset_date`.

   2. #### **EIK/VAT Uniqueness Checks (Conceptual Algorithm):**

      1. ##### **EIK:**

         When creating/updating a company, the logic queries `public.companies` to ensure `eik` is unique (either globally or per `country_id`, depending on the final DDL constraint decision for `companies.eik`).

      2. ##### **VAT:**

         (Less critical for this BLA's core, more for partner/invoice validation). If VAT validation is performed during company setup, it would involve format checks and potentially an asynchronous call to a VIES-like service for EU VAT numbers.

_(For this BLA, the "algorithms" are more about data validation rules and the correct setup of sequence parameters rather than complex mathematical computations.)_

5. ### **Integration Points**

   1. #### **Internal Hyper M v2 Modules:**

      1. ##### **Database (`public` schema):**

         Direct CRUD operations on `companies`, `company_locations`, `company_memberships`, `document_sequence_definitions`. Reads from `users`, `roles`, `countries`, `locales`, `currencies`, `company_types`.

      2. **User Authentication & Onboarding Module:** This BLA builds upon it. The "Invite New User" workflow may create a stub `users` record if the invitee is new to Hyper M v2.
      3. **Platform Subscription & Plan Management Module (Future):** User/location creation/management workflows will need to check against SaaS plan limits defined and managed by that module (feature gating).

      4. ##### **All modules that generate numbered documents:**

         These modules (Sales, Invoicing, Procurement, GRN, etc.) will consume the `document_sequence_definitions` set up via this BLA by calling the `get_next_document_number()` function.

   2. #### **External Services:**

      1. ##### **Email Service:**

         Used for sending company membership invitation emails.

      2. ##### **Authentication Service:**

         Although primarily managed in the "Auth & Onboarding BLA", it's implicitly involved as users performing these admin actions must be authenticated. Hasura relies on JWTs from this service.

      3. ##### **(Optional) VIES Service:**

         If VAT number validation for the company itself is implemented directly in the "Manage Company Profile" workflow.

6. ### **Data Integrity & Constraints (Beyond DDL)**

   1. #### **Single Default Company Location:**

      Application logic must ensure that when one `company_locations` record is set to `is_default = TRUE`, any other existing location for that same `company_id` has its `is_default` flag set to `FALSE`. (The DDL unique index `company_locations_single_default_per_company` helps enforce the end state, but application logic manages the transition).

   2. **Last Admin Protection:** Business logic must prevent the last active 'admin' user in a company from:
      1. Changing their own role to a non-admin role.
      2. Setting their own `company_memberships.status` to 'inactive' or 'removed'.
      3. This ensures the company doesn't become unmanageable. (Requires a check against other active admin memberships for that company).
   3. **Default Location Deletion Protection:** A `company_locations` record marked as `is_default = TRUE` cannot be soft-deleted until another location is designated as the default.
   4. **Document Sequence `current_number` Integrity:** As noted in Workflow 3.6.C, direct modification of `document_sequence_definitions.current_number` should be highly restricted or controlled by specific "reset" operations to prevent issuing duplicate or out-of-order document numbers, especially if documents have already been generated using that sequence in the current period.

   5. #### **SaaS Plan Limit Enforcement:**

      Before creating new users (memberships) or locations, the system must check against the company's active SaaS plan limits. This is an application-level constraint enforced by calling logic defined in the "Platform Subscription & Plan Management" BLA.

7. ### **Reporting Considerations (High-Level)**

   1. #### **User Activity per Company:**

      List of active/inactive users per company, their roles.

   2. **Company Configuration Audits:** Changes to core company settings, locations, document sequences (if audit logging is implemented for these admin actions).
   3. **Document Number Usage:** Reports on last numbers used per sequence type/location (for monitoring).

   4. #### **Platform Usage Metrics (for Hyper M v2 Admins):**

      Number of locations per company, number of users per company (relevant for SaaS billing and capacity planning).

8. ### **Open Questions / Future Considerations for this BLA**

   1. #### **Role Management Granularity:**

      This BLA assumes predefined `roles`. A future enhancement could be allowing company admins to define custom roles or customize permissions within existing roles (complex).

   2. **Advanced Document Sequence Reset Policies:** More sophisticated logic for periodic resets (e.g., automatically at year-end based on a flag, handling fiscal year variations).
   3. **Audit Logging for Admin Actions:** Implementing a detailed audit trail for all changes made in company settings, user management, and document sequence definitions.
   4. **"Transfer Company Ownership" Workflow:** A specific process if the sole admin needs to leave and transfer admin rights to another user.
   5. **"Delete Company" Workflow:** A formal process for a company admin to request deletion of their entire company and its data (soft delete initially, then hard delete after a period, considering legal data retention requirements).
   6. **Team/Department Structures within a Company:** More granular grouping of users beyond just roles (future).

   7. #### **EIK/VAT Uniqueness (reiteration):**

      Final decision on DDL constraint for `companies.eik` (global vs. per country) and its impact on validation logic.
