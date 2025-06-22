# **Business Logic Addendum: Platform Subscription & Plan Management (for Hyper M v2 itself) & Feature Gating**

**Document Version:** 1.0 Date: YYYY-MM-DD (Will be set to today's date upon completion)  
**Related DDLs:**

- public.saas_plan_type_enum
- public.saas_plans
- public.saas_feature_status_enum
- public.features
- public.saas_plan_features
- public.company_saas_subscription_status_enum
- public.company_saas_subscriptions

(All DDLs are located in the HyperM_V2_Schema_Consolidated_vX.Y.Z.sql file, under "Part V, Section J. SaaS Platform Management Module") References public.companies, public.users, public.currencies (from HyperM_V2_Schema_Consolidated_vX.Y.Z.sql)

**Primary Audience:** Development Team, Product Management

1. ### **Overview & Purpose**

   1. This BLA defines the business logic for managing the SaaS subscription plans offered by the Hyper M v2 platform to its tenant companies. It covers the definition of plans and features, the company's subscription lifecycle (including trials, plan selection, upgrades/downgrades, billing integration for platform fees), and the mechanisms for feature gating based on a company's active plan.
   2. Key objectives include:
      1. Enabling Hyper M v2 administrators to define and manage various SaaS plans (Cloud, Community Edition, Enterprise Self-Hosted) and the features included in them.
      2. Providing a clear and automated process for new tenant companies to start with a trial period.
      3. Allowing tenant companies to select, upgrade, or downgrade their SaaS plans.
      4. Integrating with payment gateways for processing subscription payments for Cloud plans (Credit Card and Bank Wire Transfer).
      5. Implementing robust feature gating to ensure companies can only access functionalities permitted by their active plan.
      6. Managing the lifecycle of company subscriptions, including renewals, handling failed payments, and downgrades to a free tier.
      7. Supporting the "CE as beta" model by allowing features to be in different states and selectively enabled for specific plan types.

2. ### **Core Entities & Their States/Statuses**

   1. #### **saas_plans**

      1. Purpose: Defines the distinct subscription plans offered by Hyper M v2 to tenant companies, detailing their characteristics, pricing (if applicable), and type (Cloud, Community Edition, Enterprise Self-Hosted).
      2. **Key fields for this BLA:** id, plan_key, name, plan_type, is_publicly_selectable, is_active, billing_interval_months, price_per_interval_exclusive_vat, currency_id, trial_days_offered, grace_period_days_after_payment_due, downgrades_to_plan_id.
      3. **Status Lifecycle for is_active (BOOLEAN):**
         1. TRUE: The plan is active. It can be assigned to new subscriptions, renewed, and is generally visible/usable within the system as per its plan_type and is_publicly_selectable flag.
         2. FALSE: The plan is inactive (archived/disabled). New companies cannot subscribe to this plan. Existing companies on this plan might continue until their current period ends, be prompted to migrate, or be grandfathered based on specific business policy (to be detailed in workflows). Renewals for inactive plans are typically disallowed.
      4. **Translations:** This entity itself (saas_plans.name, saas_plans.description) might require translations if Hyper M v2 platform administrators need to manage plan information in multiple languages for their internal admin UIs or if plan details are ever exposed externally in multiple languages. If so, a saas_plan_translations table would follow the standard JSONB pattern. _For now, this BLA assumes plan names/descriptions are managed in a single primary language for platform admin purposes._ For general translation strategy, see Core_Principle_Translations.md.

   2. #### **features**

      1. **Purpose:** Serves as a master catalog of all distinct, gateable functionalities or capabilities within the Hyper M v2 platform.
      2. **Key fields for this BLA:** id, feature_key, name, module_group, status, default_limit_value, default_limit_unit, is_core_feature.
      3. **Status Lifecycle for status (saas_feature_status_enum):**
         1. INTERNAL_ALPHA: Feature is in very early development, only for internal Hyper M team testing. Not available on any public/customer plans.
         2. EXPERIMENTAL_CE: Feature is new and primarily intended for testing and feedback within the Community Edition. May be unstable or subject to change.
         3. BETA_CLOUD: Feature is in a public beta phase, available on select Cloud plans for broader user testing and feedback. Functionality is mostly complete but may still have issues or undergo refinement.
         4. STABLE: Feature has been thoroughly tested, is considered reliable, and is generally available on relevant plans.
         5. PREMIUM: Feature is stable, reliable, and designated as a high-value offering, typically included in higher-tier paid plans.
         6. ENTERPRISE_ONLY: Feature is stable and specifically targeted for Enterprise Self-Hosted plans, often due to complexity, resource intensity, or specific enterprise needs.
         7. DEPRECATED: Feature is being phased out and will be removed in a future version. No new plan assignments; existing users may be migrated.
         8. _Transitions:_ Typically linear (e.g., INTERNAL_ALPHA \-\> EXPERIMENTAL_CE \-\> BETA_CLOUD \-\> STABLE/PREMIUM/ENTERPRISE_ONLY). A feature might also move to DEPRECATED from any active state.
      4. **Translations:** Similar to saas_plans, the features.name and features.description might require translation if these are exposed in multi-lingual contexts (e.g., in-app feature descriptions, plan comparison pages shown to tenants). If so, a feature_translations table would be needed. _For now, this BLA assumes feature names/descriptions are managed in a single primary language for platform admin purposes._

   3. #### **saas_plan_features**

      1. **Purpose:** Acts as a junction table linking saas_plans to features. It defines precisely which features are part of each plan and allows for plan-specific overrides of feature limits or configurations.
      2. **Key fields for this BLA:** saas_plan_id, feature_id, is_enabled, limit_value, configuration.
      3. **Status Lifecycle for is_enabled (BOOLEAN):**
         1. TRUE: The linked feature is enabled for the linked plan. Users on this plan can access this feature (subject to any limit_value or configuration).
         2. FALSE: The linked feature is explicitly disabled for the linked plan, even if the feature itself is STABLE or is_core_feature. This provides fine-grained control.
      4. **Translations:** Not applicable directly to this entity, as it's a linking table.

   4. #### **company_saas_subscriptions**

      1. **Purpose:** Tracks the active SaaS subscription of each tenant company to the Hyper M v2 platform, including their current plan, trial status, billing cycle information, and overall subscription lifecycle status.
      2. **Key fields for this BLA:** company_id, saas_plan_id, status, trial_started_at, trial_ends_at, current_billing_period_starts_at, current_billing_period_ends_at, next_billing_date.
      3. **Status Lifecycle for status (company_saas_subscription_status_enum):**
         1. incomplete: Initial record created, but essential information (like plan selection or initial payment setup for non-trial plans) is missing. Company cannot fully use the platform yet.
         2. trialing: Company is actively using a free trial of a specific saas_plan_id. trial_ends_at is set.  
            _Trigger for entry:_ New company onboarding (Workflow 3.7 in BLA_Module_AuthAndOnboarding.md).  
            _Transitions out:_ \-\> trial_expired (on trial_ends_at if no action), \-\> active (if converts to paid plan during trial), \-\> cancelled (if explicitly cancels trial).
         3. trial_expired: The trial_ends_at date has passed, and the company has not converted to a paid plan or selected a free tier (if available). Access may be restricted.  
            _Trigger for entry:_ Automated check when trial_ends_at is reached.  
            _Transitions out:_ \-\> active (if selects and pays for a plan), \-\> free_tier_active (if selects a free plan or is auto-downgraded), \-\> cancelled (if no action after a grace period or explicit cancellation).
         4. pending_activation: A plan has been selected (typically a paid plan after trial or an upgrade), but activation is pending an event (e.g., confirmation of a bank wire payment).  
            _Trigger for entry:_ Plan selection where immediate payment confirmation isn't possible.  
            _Transitions out:_ \-\> active (on payment confirmation), \-\> cancelled (if payment not received within a timeframe).
         5. active: The subscription is current, and the company has full access to features defined by their saas_plan_id. For paid plans, payment for the current period is successful. For free plans, it indicates they are on an active free tier.  
            _Trigger for entry:_ Successful trial conversion, successful payment for a new period, selection of a free plan.  
            _Transitions out:_ \-\> past_due (if renewal payment fails), \-\> pending_cancellation (if user requests cancellation), \-\> cancelled (if non-renewing plan ends or cancellation becomes effective).
         6. past_due: Payment for the current/next billing period is overdue. Notifications sent. Access might be restricted after a grace period defined in saas_plans.grace_period_days_after_payment_due.  
            _Trigger for entry:_ Failed scheduled payment attempt for renewal.  
            _Transitions out:_ \-\> active (if payment is successfully made), \-\> payment_failed (if subsequent attempts fail), \-\> cancelled or free_tier_active (if payment not resolved after grace period).
         7. payment_failed: Multiple payment attempts have failed. Subscription is at high risk of cancellation/downgrade. Access likely restricted.  
            _Trigger for entry:_ Repeated failed payment attempts.  
            _Transitions out:_ \-\> active (if payment is successfully made, possibly via manual intervention or updated payment method), \-\> cancelled or free_tier_active (if not resolved).
         8. pending_cancellation: The company has requested to cancel their subscription. The subscription remains active (or in its current billable state) until cancellation_effective_at (typically the end of the current paid billing period).  
            _Trigger for entry:_ User initiates cancellation request.  
            _Transitions out:_ \-\> cancelled (on cancellation_effective_at), or potentially back to active (if user retracts cancellation before it's effective).
         9. cancelled: The subscription is no longer active and will not renew. Access to paid features is revoked. The company might be moved to a read-only state or to the features defined by saas_plans.downgrades_to_plan_id (if any). Data retention policies apply.  
            _Trigger for entry:_ cancellation_effective_at reached, or direct cancellation after non-payment/trial expiry without conversion.  
            _Transitions out:_ Unlikely to transition out without new plan selection/intervention.
         10. free_tier_active: The company is on a designated "Free Tier" plan. This often occurs after a trial expires without conversion to a paid plan, or a paid plan is cancelled/downgraded due to non-payment. Functionality is limited to what the free tier plan offers.  
             _Trigger for entry:_ Auto-downgrade from trial_expired or past_due/payment_failed.  
             _Transitions out:_ \-\> active (if upgrades to a paid plan).
      4. **Translations:** Not applicable directly to this entity.

3. ### **Key Workflows & Processes**

   1. #### **Workflow: (Platform Admin) Manage SaaS Plans**

      1. ##### **Sub-Workflow: Create New SaaS Plan**

         1. **Trigger / Entry Point:**  


- A Hyper M v2 Platform Administrator navigates to the "SaaS Plan Management" section in the platform's super-admin interface.
- Admin clicks "Create New SaaS Plan."  
  2. **Pre-conditions / Required Inputs (from Platform Admin):**

  1.  plan_key (TEXT, UNIQUE, NOT NULL)  
      2. name (TEXT, NOT NULL)  
       3. description (TEXT, Optional)  
       4. plan_type (ENUM saas_plan_type_enum, NOT NULL)  
       5. is_publicly_selectable (BOOLEAN, NOT NULL)  
       6. is_active (BOOLEAN, NOT NULL, typically TRUE for new plans)  
       7. _If plan_type is 'CLOUD' and it's a paid plan:_  
       1. billing_interval_months (INTEGER, NOT NULL)  
       2. price_per_interval_exclusive_vat (NUMERIC, NOT NULL)  
       3. currency_id (UUID FK to public.currencies, NOT NULL)  
       8. trial_days_offered (INTEGER, NOT NULL, can be 0\)  
       9. grace_period_days_after_payment_due (INTEGER, NOT NULL, can be 0\)  
       10. downgrades_to_plan_id (UUID FK to public.saas_plans, Optional, for defining downgrade path)  
       11. display_order (INTEGER, NOT NULL)  
      3. **User Interface Considerations (Functional):**

      1.  Form with input fields for all saas_plans attributes.
      2.  Dropdowns for plan_type, currency_id, downgrades_to_plan_id (populated from existing plans).
      3.  Conditional visibility of billing fields based on plan_type.
      4.  **Step-by-Step Logic & Rules:**
          1.  **Platform Admin inputs plan details.**
          2.  **Client-Side Validation:** Basic format checks, required fields.
          3.  **Server-Side Submission:** Data submitted to a dedicated backend endpoint for platform administration.
          4.  **Server-Side Input Validation:**
              1. Verify all required fields based on plan_type.
              2. Validate plan_key uniqueness in public.saas_plans.
              3. Validate FKs (currency_id, downgrades_to_plan_id).
              4. Validate constraints (e.g., billing_interval_months \> 0 if provided, trial_days_offered \>= 0).
          5.  **Create saas_plans Record:**
              1. INSERT a new record into public.saas_plans with the provided and validated data.
      5.  **Post-conditions / Outputs:**
          1.  A new record exists in public.saas_plans.
          2.  Platform Admin is typically redirected to a view where they can link features to this new plan (see Workflow 3.2).
          3.  **User Feedback (UI for Platform Admin):** "SaaS Plan '\[Plan Name\]' created successfully."
      6.  **Error Handling / Exceptional Flows:**
          1.  plan_key already exists.
          2.  Invalid input data or FK violations.
          3.  Database errors.
      7.  **Permissions / Authorization Notes:**
          1.  Requires Hyper M v2 Platform Super Administrator privileges.

  2.  ##### **Sub-Workflow: Edit Existing SaaS Plan**

      1. Trigger / Entry Point:
         1. Platform Admin selects an existing plan from the "SaaS Plan Management" list.
      2. **Pre-conditions / Required Inputs:**
         1. saas_plan_id of the plan to edit.
         2. Admin can modify most fields.
      3. **User Interface Considerations (Functional):**
         1. Form pre-filled with current plan details.
      4. **Step-by-Step Logic & Rules:**
         1. **Platform Admin modifies plan details.**
         2. **Client-Side Validation.**
         3. **Server-Side Submission.**
         4. **Server-Side Input Validation:**
            1. plan_key cannot be changed (as it's a programmatic identifier). If a change is needed, a new plan should be created.
            2. Validate all other modified fields.
            3. **Considerations if changing pricing/billing interval:** How does this affect existing subscribers on this plan?
            4. _Business Policy:_ Changes might only apply to new subscriptions or renewals after the change. Existing subscriptions might be grandfathered in at their original terms until their current period ends, or a migration path/notification process is initiated. This needs careful definition. For now, assume changes apply to new subscriptions/renewals.
            5. **Considerations if changing is_active to FALSE:**
               1. Prevent new subscriptions.
               2. Existing subscriptions: Define policy (e.g., allow to run until period end, then force migration or use downgrades_to_plan_id).
            6. **Update saas_plans Record:**
               1. UPDATE the public.saas_plans record for the given saas_plan_id.
      5. **Post-conditions / Outputs:**
         1. The public.saas_plans record is updated.
         2. **User Feedback (UI for Platform Admin):** "SaaS Plan '\[Plan Name\]' updated successfully."
      6. **Error Handling / Exceptional Flows:**
         1. Invalid input data.
         2. Database errors.
         3. Attempting to set downgrades_to_plan_id to itself.
      7. **Permissions / Authorization Notes:**
         1. Requires Hyper M v2 Platform Super Administrator privileges.

  3.  **Sub-Workflow: Delete SaaS Plan (Logical Deletion / Archiving)**

_Note: True deletion of a plan with active subscribers is highly problematic. This workflow focuses on making a plan inactive._

1. **Trigger / Entry Point:**

   1. Platform Admin selects an existing plan and chooses to "Deactivate" or "Archive" it.  
      2. **Pre-conditions / Required Inputs:**

      1. saas_plan_id of the plan to deactivate.
      2. **User Interface Considerations (Functional):**
         1. Confirmation prompt: "Are you sure you want to deactivate plan '\[Plan Name\]'? New subscriptions will be disabled. Existing subscriptions may need to be migrated."
      3. **Step-by-Step Logic & Rules:**
         1. **Platform Admin confirms deactivation.**
         2. **Check for Active Subscriptions:**
            1. Query public.company_saas_subscriptions for any records linked to this saas_plan_id with an active-like status (e.g., 'trialing', 'active', 'past_due', 'pending_activation').
            2. If active subscriptions exist, the admin should be warned. The system might prevent deactivation or require a migration strategy first (e.g., ensure downgrades_to_plan_id is set or manually migrate users).
            3. _Business Policy:_ Define how to handle existing subscribers. Simplest is to prevent deactivation if active users exist unless a clear downgrade/migration path is defined.
         3. **Update saas_plans Record:**
            1. Set is_active \= FALSE for the given saas_plan_id.
      4. **Post-conditions / Outputs:**
         1. The saas_plans.is_active field is set to FALSE.
         2. The plan is no longer available for new subscriptions.
         3. **User Feedback (UI for Platform Admin):** "SaaS Plan '\[Plan Name\]' deactivated."
      5. **Error Handling / Exceptional Flows:**
         1. Plan not found.
         2. Attempting to deactivate a plan with active subscriptions without a defined migration/downgrade policy.
      6. **Permissions / Authorization Notes:**
         1. Requires Hyper M v2 Platform Super Administrator privileges.

   2. #### **Workflow: (Platform Admin) Manage Features & Plan Assignments**

      1. ##### **Sub-Workflow: Create New Feature Definition**

         1. **Trigger / Entry Point:**
            1. Platform Admin navigates to "Feature Management" section.
            2. Admin clicks "Create New Feature."
         2. **Pre-conditions / Required Inputs (from Platform Admin):**
            1. feature_key (TEXT, UNIQUE, NOT NULL)
            2. name (TEXT, NOT NULL)
            3. description (TEXT, Optional)
            4. module_group (TEXT, Optional)
            5. status (ENUM saas_feature_status_enum, NOT NULL)
            6. default_limit_value (NUMERIC, Optional)
            7. default_limit_unit (TEXT, Optional, required if default_limit_value is set)
            8. is_core_feature (BOOLEAN, NOT NULL)
            9. availability_notes (TEXT, Optional)
         3. **User Interface Considerations (Functional):**
            1. Form with input fields for all features attributes.
            2. Dropdown for status.
         4. **Step-by-Step Logic & Rules:**
            1. **Platform Admin inputs feature details.**
            2. **Client-Side Validation.**
            3. **Server-Side Submission.**
            4. **Server-Side Input Validation:**
               1. Verify all required fields.
               2. Validate feature_key uniqueness in public.features.
               3. If default_limit_value is provided, default_limit_unit must also be provided.
            5. **Create features Record:**
               1. INSERT a new record into public.features.
         5. **Post-conditions / Outputs:**
            1. A new record exists in public.features.
            2. **User Feedback (UI for Platform Admin):** "Feature '\[Feature Name\]' created successfully."
         6. **Error Handling / Exceptional Flows:**
            1. feature_key already exists.
            2. Invalid input data.
         7. **Permissions / Authorization Notes:**
            1. Requires Hyper M v2 Platform Super Administrator privileges.

      2. ##### **Sub-Workflow: Edit Existing Feature Definition**

         1. **Trigger / Entry Point:**
            1. Platform Admin selects an existing feature from the "Feature Management" list.
         2. **Pre-conditions / Required Inputs:**
            1. feature_id of the feature to edit.
         3. **User Interface Considerations (Functional):**
            1. Form pre-filled with current feature details.
         4. **Step-by-Step Logic & Rules:**
            1. **Platform Admin modifies feature details.**
            2. feature_key should generally not be changed once established, as application code relies on it.
            3. Changing status (e.g., from EXPERIMENTAL_CE to STABLE) has implications for which plans might now be able to include it.
            4. Changing default_limit_value or is_core_feature may impact existing plan configurations or behavior if not overridden at the plan-feature level.
            5. **Server-Side Validation and Update:** UPDATE the public.features record.
         5. **Post-conditions / Outputs:**
            1. The public.features record is updated.
            2. **User Feedback (UI for Platform Admin):** "Feature '\[Feature Name\]' updated."
         6. **Error Handling / Exceptional Flows:**
            1. Invalid input data.
         7. **Permissions / Authorization Notes:**
            1. Requires Hyper M v2 Platform Super Administrator privileges.

      3. ##### **Sub-Workflow: Assign/Update Features for a SaaS Plan**

         1. **Trigger / Entry Point:**
            1. Platform Admin is viewing/editing a specific saas_plan (Workflow 3.1.2).
            2. There's a section to manage "Included Features" for this plan.
         2. **Pre-conditions / Required Inputs (from Platform Admin):**
            1. saas_plan_id.
            2. List of feature_ids to associate with the plan.
            3. For each associated feature:
               1. is_enabled (BOOLEAN)
               2. limit_value (NUMERIC, Optional override for the feature's default limit)
               3. configuration (JSONB, Optional plan-specific feature config)
         3. **User Interface Considerations (Functional):**
            1. A multi-select list or checklist of all available features.
            2. For each selected/assigned feature, input fields for is_enabled (default TRUE), limit_value (placeholder shows feature default), configuration (e.g., a JSON editor or structured fields).
            3. Clear indication of feature status (e.g., EXPERIMENTAL_CE, STABLE) to guide assignment.
         4. **Step-by-Step Logic & Rules:**
            1. **Platform Admin selects features and configures their plan-specific settings.**
            2. **Server-Side Submission:** The list of feature assignments (including existing ones to be updated and new ones to be added, or ones to be removed) for the saas_plan_id is submitted.
            3. **Process Feature Assignments:**
               1. For each feature assignment:
                  1. If a record exists in public.saas_plan_features for the saas_plan_id and feature_id: UPDATE it with new is_enabled, limit_value, configuration.
                  2. If no record exists: INSERT a new record into public.saas_plan_features.
                  3. If a feature was previously assigned but is no longer in the submitted list for the plan: DELETE the corresponding record from public.saas_plan_features.
               2. Validate that limit_value is only provided for features that have a default_limit_unit defined in the features table (i.e., quantifiable features).
         5. **Post-conditions / Outputs:**
            1. Records in public.saas_plan_features are created, updated, or deleted to reflect the plan's feature set.
            2. **User Feedback (UI for Platform Admin):** "Plan features updated successfully."
         6. **Error Handling / Exceptional Flows:**
            1. Invalid feature_id.
            2. Inconsistent limit overrides (e.g., providing a limit for an on/off feature).
         7. **Permissions / Authorization Notes:**
            1. Requires Hyper M v2 Platform Super Administrator privileges.

   3. #### **Workflow: Initial Company Trial Onboarding**

      1. Trigger / Entry Point:
         1. This workflow is triggered as part of "Workflow 3.7: Initial Company Onboarding (Creating the First Company)" in BLA_Module_AuthAndOnboarding.md, specifically after the companies record and initial company_memberships record are successfully created.
      2. **Pre-conditions / Required Inputs (System Internal):**
         1. A new companies.id has just been created.
         2. System configuration defining the "Default Trial Plan Key" (e.g., 'CLOUD_PREMIUM_TRIAL' or 'CE_DEFAULT_TRIAL').
      3. **User Interface Considerations (Functional):**
         1. As per the "Initial Company Onboarding" UI (from BLA_Module_AuthAndOnboarding.md), the user might be informed that "Your new company will start with a \[Trial Plan Name\] 30-day free trial."
         2. No direct user input for this specific sub-workflow, it's an automated system step.
      4. **Step-by-Step Logic & Rules:**
         1. **Identify Default Trial Plan:**
            1. Retrieve the saas_plans.id (let's call it default_trial_plan_id) and saas_plans.trial_days_offered from public.saas_plans WHERE plan_key matches the system-configured "Default Trial Plan Key" and is_active \= TRUE.
            2. If no such plan is found or trial_days_offered is 0, this indicates a configuration error or a policy of no default trial. Log an error/alert for platform admins. For this BLA, assume a valid trial plan is configured.
         2. **Calculate Trial End Date:**
            1. trial_ends_at_timestamp \= now() \+ (saas_plans.trial_days_offered || ' days')::interval.
         3. **Create company_saas_subscriptions Record:**
            1. INSERT a new record into public.company_saas_subscriptions:
               1. company_id: The newly created [companies.id](http://companies.id).
               2. saas_plan_id: default_trial_plan_id.
               3. status: 'trialing'.
               4. trial_started_at: now().
               5. trial_ends_at: trial_ends_at_timestamp.
               6. current_billing_period_starts_at: NULL (not yet on a paid cycle).
               7. current_billing_period_ends_at: NULL.
               8. next_billing_date: NULL.
         4. **(Optional) Update companies.settings:**
            1. If not already handled during company creation, the companies.settings JSONB field could be updated with a key like saas_trial_active: true or current_saas_plan_key: \[default_trial_plan_key\]. This is denormalization for quick checks but the company_saas_subscriptions table is the source of truth.
      5. **Post-conditions / Outputs:**
         1. A new record exists in public.company_saas_subscriptions for the new company with status \= 'trialing' and a defined trial_ends_at.
         2. The company is now officially on a trial plan.
      6. **Error Handling / Exceptional Flows:**
         1. Default trial plan not found or misconfigured in saas_plans.
         2. Database error during INSERT into company_saas_subscriptions.
      7. **Permissions / Authorization Notes:**
         1. This is an automated system process, typically triggered by an authenticated user action (company creation) but executed with system-level privileges to create the subscription record.

   4. #### **Workflow: Trial Expiry Management & Notifications**

      1. **Trigger / Entry Point:**
         1. **Automated Scheduled Task/Job Runner:** Runs periodically (e.g., daily) to check for expiring or recently expired trials.
         2. **On-Demand Check:** When a user from a company logs in or accesses certain features, the system might check their company_saas_subscriptions.trial_ends_at and status.
      2. **Pre-conditions / Required Inputs (for Scheduled Task):**
         1. Access to public.company_saas_subscriptions and public.saas_plans.
         2. System configuration for notification lead times (e.g., notify 7 days before, 3 days before, on day of expiry).
      3. **User Interface Considerations (Functional):**
         1. **In-App Notifications/Banners:** Displayed to company admins within Hyper M v2:
            1. "Your trial for \[Plan Name\] expires in X days. Upgrade now to keep your features."
            2. "Your trial has expired. Please select a plan to continue."
         2. **Email Notifications:** Sent to company admin(s).
      4. **Step-by-Step Logic & Rules (Scheduled Task Focused):**
         1. **Identify Trials Nearing Expiry:**
            1. Query public.company_saas_subscriptions for records where:
               1. status \= 'trialing'.
               2. trial_ends_at is within the configured notification windows (e.g., trial_ends_at \<= now() \+ '7 days'::interval AND trial_ends_at \> now()).
         2. **Send Pre-Expiry Notifications:**
            1. For each identified subscription:
               1. Determine if a notification for that specific lead time (e.g., 7-day warning) has already been sent (e.g., by checking a log or a flag on company_saas_subscriptions.metadata).
               2. If not sent, dispatch an email and potentially create an in-app notification for the company's admin users.
               3. Email content should highlight benefits of upgrading, remaining trial duration, and a clear Call To Action (link to upgrade/plan selection page).
               4. Log that the notification was sent.
         3. **Identify Expired Trials:**
            1. Query public.company_saas_subscriptions for records where:
               1. status \= 'trialing'.
               2. trial_ends_at \<= now().
         4. **Process Expired Trials:**
            1. For each expired trial:
               1. UPDATE public.company_saas_subscriptions SET status \= 'trial_expired', updated_at \= now().
               2. Dispatch an "Trial Expired" email and create an in-app notification.
               3. The email should urge plan selection and warn about potential feature restrictions if no action is taken.
               4. _Note on Feature Access:_ Once status becomes 'trial_expired', the feature gating logic (Workflow 3.8) should enforce restrictions based on what a 'trial_expired' status permits (likely very limited access, prompting plan selection).
         5. **Identify Post-Expiry Grace Period Expiry (If Applicable):**
            1. If a saas_plans.downgrades_to_plan_id (e.g., a "Free Tier") is configured for the trial plan, and trial_expired status has persisted for a certain grace period without user action:
               1. Query public.company_saas_subscriptions for records where status \= 'trial_expired' and updated_at (or trial_ends_at) is older than X days (configurable grace period for trial_expired state).
               2. Retrieve downgrades_to_plan_id for the original trial plan from saas_plans.
               3. If downgrades_to_plan_id exists:
                  1. UPDATE public.company_saas_subscriptions:
                     1. SET saas_plan_id \= \[downgrades_to_plan_id\].
                     2. SET status \= 'free_tier_active' (or 'active' if the free tier is just another active plan).
                     3. Clear trial dates: trial_started_at \= NULL, trial_ends_at \= NULL.
                     4. Clear billing dates: current_billing_period_starts_at \= NULL, etc.
                     5. updated_at \= now().
                  2. Send notification: "Your trial has ended, and your account has been moved to our Free Tier."
               4. If no downgrades_to_plan_id (or if it's the same as the trial plan effectively meaning no free tier downgrade path):
                  1. The subscription might move to status \= 'cancelled' or access severely restricted.
                  2. _Business Policy:_ Define behavior if no free tier downgrade. E.g., account becomes read-only or suspended after trial_expired \+ grace.
      5. **Post-conditions / Outputs:**
         1. Relevant companies receive pre-expiry or expiry notifications.
         2. company_saas_subscriptions.status updated for expired trials.
         3. Companies might be automatically downgraded to a free tier after a grace period.
      6. **Error Handling / Exceptional Flows:**
         1. Email service failure (notifications should be re-queueable or logged).
         2. Errors updating company_saas_subscriptions.
      7. **Permissions / Authorization Notes:**
         1. Scheduled task runs with system privileges.
         2. In-app notifications target users with admin roles within their respective companies.

   5. #### **Workflow: (Company Admin) Select / Change SaaS Plan & Initiate Payment**

      1. **Trigger / Entry Point:**
         1. Company admin, after their trial expires (status \= 'trial_expired'), is prompted to select a plan.
         2. Company admin, while on an active trial (status \= 'trialing'), decides to upgrade to a paid plan.
         3. Company admin, on an existing plan (status \= 'active' or 'free_tier_active'), navigates to "Subscription Management" or "Billing" section within their company settings in Hyper M v2 and chooses to "Change Plan" or "Upgrade."
      2. **Pre-conditions / Required Inputs (from Company Admin):**
         1. Authenticated company admin user.
         2. selected_saas_plan_id (UUID of the desired new plan from public.saas_plans where is_publicly_selectable \= TRUE and plan_type \= 'CLOUD' and is_active \= TRUE).
         3. Selected billing_interval_months (if the selected plan offers multiple, e.g., monthly vs. annual options for the same plan features – this implies saas_plans might need to distinguish between monthly/annual versions of a "plan level" or the UI presents pricing for different intervals of the same saas_plan_id). _For simplicity in DDL, assume saas_plans.billing_interval_months is fixed per plan record. If a "Premium Monthly" and "Premium Annual" are different options, they are different saas_plans records._
         4. Payment method details (for paid plans):
            1. Credit Card: Card number, expiry, CVC, billing address.
            2. Bank Wire Transfer: Indication of intent to pay via wire.
      3. **User Interface Considerations (Functional):**
         1. **Plan Selection Page:**
            1. Displays available saas_plans (filtered by is_publicly_selectable=TRUE, is_active=TRUE, plan_type='CLOUD').
            2. Clear presentation of features, pricing (price_per_interval_exclusive_vat, billing_interval_months), and currency for each plan.
            3. "Select Plan" or "Upgrade/Downgrade to this Plan" buttons.
         2. **Checkout/Payment Page (for paid plans):**
            1. Summary of selected plan and total amount due for the first period.
            2. Input fields for Credit Card details (integrated with a payment gateway's secure form/elements).
            3. Option to select "Pay by Bank Wire Transfer," which then displays payment instructions and reference numbers.
            4. Order confirmation details before final submission.
            5. Calculations for pro-rated charges/credits if changing plans mid-cycle (see 3.5.4.5).
      4. **Step-by-Step Logic & Rules:**
         1. **Load Available Plans:** Fetch saas_plans (where is_publicly_selectable=TRUE, is_active=TRUE, plan_type='CLOUD') and display them to the admin. Also fetch current company_saas_subscriptions record for context.
         2. **Admin Selects New Plan:** Admin chooses a selected_saas_plan_id.
         3. **Determine Action (New Subscription, Upgrade, Downgrade, Crossgrade):**
            1. Compare selected_saas_plan_id with the current_company_subscription.saas_plan_id.
            2. Identify if it's an upgrade (e.g., higher price/more features), downgrade (lower price/fewer features), or crossgrade (different features, similar price point). This affects pro-ration and effective change date.
         4. **Calculate Initial/Pro-rated Amount Due (if applicable):**
            1. **If New Subscription (e.g., from trial_expired or free_tier_active to a paid plan):** Amount due is selected_plan.price_per_interval_exclusive_vat.
            2. **If Changing Plans Mid-Cycle (Upgrade/Downgrade from an existing paid plan):**
               1. _Business Policy for Pro-ration:_
                  1. **Option A (Immediate Change, Pro-rated):** Calculate unused portion of current plan's paid period. Calculate cost of new plan for remainder of period. Net charge or credit applied. New plan features effective immediately.
                  2. **Option B (Change at End of Current Period):** No pro-ration. Current plan runs to end of its paid period (current_billing_period_ends_at). New plan and its price become effective on next_billing_date. Old features remain until then.
                  3. _For this BLA, let's assume **Option B (Change at End of Current Period)** for simplicity for downgrades and potentially immediate for critical upgrades. The exact policy needs to be firm._
                  4. _If immediate upgrade with pro-ration:_ The calculation involves days remaining, daily rates of old/new plans.
            3. Display the calculated amount clearly to the admin.
         5. **Admin Provides Payment Information (if selected_plan.price_per_interval_exclusive_vat \> 0):**
            1. **If Credit Card:**
               1. Admin submits card details via payment gateway's secure iframe/elements.
               2. Client-side obtains a payment method token from the gateway.
               3. Token submitted to Hyper M v2 backend.
            2. **If Bank Wire Transfer:**
               1. Admin indicates intent.
         6. **Process Payment & Update Subscription (Backend Logic):**
            1. Let current_sub be the existing company_saas_subscriptions record.
            2. Let new_plan be the saas_plans record for selected_saas_plan_id.
            3. **If Credit Card Payment:**
               1. Backend uses payment method token to attempt charging the amount due via Payment Gateway API.
               2. **If Payment Successful:**
                  1. Record payment success (details in a separate saas_payments table \- _to be defined, or simply update last_payment_succeeded_at_).
                  2. Proceed to update company_saas_subscriptions (see step 7).
               3. **If Payment Failed:**
                  1. Record payment failure (last_payment_failed_at, last_payment_failed_reason).
                  2. Return error to UI: "Payment failed: \[Gateway Message\]. Please check your card details or try another method."
                  3. Subscription status might become/remain payment_failed or trial_expired.
            4. **If Bank Wire Transfer Selected:**
               1. No immediate payment processing.
               2. Update company_saas_subscriptions status to pending_activation.
               3. Store selected_saas_plan_id (e.g., in company_saas_subscriptions.metadata or a dedicated field pending_plan_id) if the change is not immediate.
               4. Display payment instructions (bank details, unique reference code for reconciliation) to the admin.
               5. Explain that plan will activate upon payment confirmation.
            5. **If Selected Plan is Free (e.g., downgrading to Free Tier from trial_expired or a paid plan):**
               1. No payment processing needed.
               2. Proceed to update company_saas_subscriptions (see step 7).
         7. **Update company_saas_subscriptions Record (on successful payment or selection of free/bank wire plan):**
            1. saas_plan_id: new_plan.id.
            2. status:
               1. 'active' if payment successful for paid plan, or if selected plan is free.
               2. 'pending_activation' if bank wire selected for paid plan.
            3. trial_started_at: NULL (trial is over or wasn't applicable).
            4. trial_ends_at: NULL.
            5. current_billing_period_starts_at:
               1. now() if new subscription or immediate upgrade.
               2. current_sub.current_billing_period_ends_at \+ 1 day if change effective at next cycle.
               3. NULL for free plans.
            6. current_billing_period_ends_at:
               1. current_billing_period_starts_at \+ new_plan.billing_interval_months (adjust for months).
               2. NULL for free plans.
            7. next_billing_date: current_billing_period_ends_at \+ 1 day (or derived from it). NULL for free plans or non-renewing plans.
            8. last_payment_succeeded_at: now() (if CC payment was successful).
            9. updated_at: now().
            10. Clear any cancellation_requested_at if user is actively re-subscribing/changing plan.
         8. **(Optional) Send Confirmation Email:** Email to company admin confirming plan change and next billing date.
      5. **Post-conditions / Outputs:**
         1. company_saas_subscriptions record is updated with the new plan, status, and billing dates.
         2. Payment is processed (for CC) or pending (for Bank Wire).
         3. Feature access for the company will now be governed by the new saas_plan_id (as per Workflow 3.8).
         4. **User Feedback (UI):**
            1. Success message: "Your subscription to \[New Plan Name\] is now active."
            2. Or: "Your request to switch to \[New Plan Name\] is pending payment confirmation (Bank Wire)."
      6. **Error Handling / Exceptional Flows:**
         1. Selected plan not found or inactive.
         2. Credit card payment failure (declined, insufficient funds, gateway error).
         3. Pro-ration calculation errors (if complex pro-ration is implemented).
         4. Database errors.
      7. **Permissions / Authorization Notes:**
         1. Requires company admin role for the active company.

   6. #### **Workflow: Bank Wire Payment Reconciliation & Activation**

      1. **Trigger / Entry Point:**
         1. Hyper M v2 Finance/Ops team receives notification of a bank wire payment or reviews bank statements.
         2. A unique reference code (provided to the company admin during plan selection) links the payment to a company and pending subscription.
      2. **Pre-conditions / Required Inputs (for Platform Admin/Finance):**
         1. Payment confirmation details (amount, reference code, date).
         2. Access to an internal admin tool to manage company subscriptions.
      3. **User Interface Considerations (Functional \- Internal Admin Tool):**
         1. Interface to search for company subscriptions by reference code or company ID.
         2. Ability to view subscriptions with status \= 'pending_activation'.
         3. Action to "Confirm Payment & Activate Plan."
      4. **Step-by-Step Logic & Rules:**
         1. **Platform Admin identifies the incoming payment and matches it to a company subscription** (e.g., using the unique reference code).
         2. **Verify Payment:** Confirm amount received matches expected amount for the selected plan.
         3. **Platform Admin triggers "Confirm Payment" action in the internal admin tool.**
         4. **System Updates company_saas_subscriptions Record:**
            1. Query for the company_saas_subscriptions record (where status \= 'pending_activation' and matches company/reference).
            2. Let new_plan be the plan they intended to activate (could be stored in saas_plan_id already or in metadata if it was a pending change).
            3. SET status \= 'active'.
            4. SET last_payment_succeeded_at \= now() (or actual payment confirmation date).
            5. SET current_billing_period_starts_at \= now() (or date payment was effective).
            6. SET current_billing_period_ends_at \= current_billing_period_starts_at \+ new_plan.billing_interval_months.
            7. SET next_billing_date \= current_billing_period_ends_at \+ 1 day.
            8. Clear any pending activation metadata.
            9. updated_at \= now().
         5. **Send Activation Confirmation Email:** Notify company admin that their payment is confirmed and their plan is now active.
      5. **Post-conditions / Outputs:**
         1. company_saas_subscriptions.status is updated to 'active'.
         2. Billing cycle dates are set.
         3. Company gains access to features of the activated plan.
      6. **Error Handling / Exceptional Flows:**
         1. Payment reference not found or mismatched.
         2. Partial payment received (requires manual intervention/policy).
         3. Subscription record not in pending_activation status.
      7. **Permissions / Authorization Notes:**
         1. Requires Hyper M v2 Platform Finance/Ops role with access to the internal subscription management tool.

   7. #### **Workflow: Automatic Subscription Renewal & Payment Processing (Recurring)**

      1. **Trigger / Entry Point:**
         1. **Automated Scheduled Task/Job Runner:** Runs periodically (e.g., daily) to identify subscriptions due for renewal.
      2. **Pre-conditions / Required Inputs (for Scheduled Task):**
         1. Access to `public.company_saas_subscriptions` and `public.saas_plans`.
         2. Secure access to payment gateway integration for processing recurring payments (using stored payment method tokens/customer profiles where applicable and compliant).
      3. **User Interface Considerations (Functional):**
         1. Generally transparent to the user unless a payment fails.
         2. Company admins can view their "Next Billing Date" and "Current Plan" in their subscription management UI.
         3. Pre-renewal notification emails (optional but good practice).
      4. **Step-by-Step Logic & Rules (Scheduled Task Focused):**
         1. **Identify Subscriptions Due for Renewal:**
            1. Query `public.company_saas_subscriptions` for records where:
               1. `status = 'active'`.
               2. `next_billing_date IS NOT NULL` AND `next_billing_date <= CURRENT_DATE`.
               3. The `saas_plan_id` corresponds to a plan that is not free (i.e., `saas_plans.price_per_interval_exclusive_vat > 0`).
         2. **(Optional) Send Pre-Renewal Notification Email:**
            1. A few days _before_ `next_billing_date` (e.g., 3-7 days), send an email reminding the company admin of the upcoming renewal, amount, and charge date. This allows them to update payment methods if needed.
         3. **For Each Subscription Due for Renewal:**
            1. Let `current_sub` be the `company_saas_subscriptions` record.
            2. Let `plan` be the associated `saas_plans` record.
            3. Retrieve stored payment method details/token for the company (e.g., from `company_saas_subscriptions.metadata` or a secure vault linked to the company/payment gateway customer ID).
            4. **Attempt Payment via Payment Gateway:**
               1. Initiate a charge for `plan.price_per_interval_exclusive_vat` (plus applicable taxes if dynamically calculated by Hyper M).
               2. Set `current_sub.last_payment_attempted_at = now()`.
               3. **If Payment Successful:**
                  1. UPDATE `public.company_saas_subscriptions`:
                     1. `last_payment_succeeded_at = now()`.
                     2. `current_billing_period_starts_at = current_sub.next_billing_date`.
                     3. `current_billing_period_ends_at = current_sub.next_billing_date + (plan.billing_interval_months || ' months')::interval - '1 day'::interval` (or similar logic to correctly set the end of the new period).
                     4. `next_billing_date = (new)current_billing_period_ends_at + '1 day'::interval`.
                     5. `status = 'active'` (should already be, but confirm).
                     6. `last_payment_failed_reason = NULL`.
                     7. `updated_at = now()`.
                  2. (Optional) Send a "Payment Successful / Receipt" email.
                  3. (Optional) Generate an invoice for Hyper M v2's own accounting for this SaaS fee.
               4. **If Payment Fails:**
                  1. UPDATE `public.company_saas_subscriptions`:
                     1. `status = 'past_due'` (or `'payment_failed'` if it's the first failure leading directly to this status based on policy).
                     2. `last_payment_failed_reason = [Gateway Error Message]`.
                     3. `updated_at = now()`.
                  2. **Initiate Dunning Process (Sub-Workflow):**
                     1. Send "Payment Failed" notification email to company admin, instructing them to update payment details and retry.
                     2. Schedule further retry attempts if payment gateway supports it or if Hyper M has its own retry logic (e.g., retry in 1 day, then 3 days). This involves updating `last_payment_attempted_at` on retries.
                     3. If multiple retries fail over the `plan.grace_period_days_after_payment_due`:
                        1. The status might change to `'payment_failed'` (if not already).
                        2. After the grace period expires (checked by another part of the scheduled task or this one):
                        - If `plan.downgrades_to_plan_id` is set:
                        - UPDATE `company_saas_subscriptions` to switch to the downgrade plan, set `status = 'free_tier_active'` (or `'active'` if downgrade is to a lower paid tier and that's the policy), clear billing dates.
                        - Send "Subscription Downgraded due to Non-Payment" email.
                     - If no downgrade plan:
                       - UPDATE `company_saas_subscriptions` SET `status = 'cancelled'`.
                       - Send "Subscription Cancelled due to Non-Payment" email.
                       - Access to features is revoked as per `'cancelled'` status (Workflow 3.8).
      5. **Post-conditions / Outputs:**
         1. Company subscriptions are renewed, and billing periods updated.
         2. Or, if payment fails, subscription status is updated, and dunning/downgrade processes are initiated.
      6. **Error Handling / Exceptional Flows:**
         1. Payment gateway errors (connectivity, configuration).
         2. Stored payment method is invalid or expired before attempting charge.
         3. Errors updating `company_saas_subscriptions`.
      7. **Permissions / Authorization Notes:**
         1. Scheduled task runs with system privileges.

   8. #### **Workflow: Feature Gating & Access Control Check**

      1. **Trigger / Entry Point:**
         1. A user associated with a company attempts to access any feature, module, or perform an action within Hyper M v2.
         2. This check happens on the backend (Hasura permissions, custom service logic) and can also inform UI rendering on the frontend.
      2. **Pre-conditions / Required Inputs (System Internal):**
         1. Authenticated user's `user_id`.
         2. Active `company_id` context for the user.
         3. The `feature_key` (from `public.features`) of the functionality being accessed.
      3. **User Interface Considerations (Functional):**
         1. **Frontend:** UI elements (buttons, menu items, sections) corresponding to features not available under the company's current plan should be hidden, disabled, or display an "upgrade required" prompt.
         2. **Backend:** API requests for disallowed features should be rejected.
      4. **Step-by-Step Logic & Rules (Conceptual \- typically part of middleware or service logic):**
         1. **Identify Company's Active Subscription and Plan:**
            1. For the given `company_id`, query `public.company_saas_subscriptions` to get the current `saas_plan_id` and `status`.
         2. **Handle Non-Active Subscription Statuses:**
            1. If `company_saas_subscriptions.status` is NOT one that permits full feature access (e.g., not `'active'`, not `'trialing'` for features included in the trial plan, not `'free_tier_active'` for features included in the free plan), then access to most features should be denied or severely limited.
            2. Specific statuses like `'trial_expired'`, `'past_due'`, `'payment_failed'`, `'cancelled'` should typically restrict access significantly, perhaps only allowing access to billing/subscription management pages.
            3. _Business Policy:_ Define exactly what features (if any, beyond subscription management) are accessible under each non-fully-active status.
         3. **Check Feature Enablement for the Active Plan:**
            1. If the subscription status permits access (e.g., `'active'`, `'trialing'`):
               1. Query `public.saas_plan_features` for a record matching the `company_saas_subscriptions.saas_plan_id` and the requested `feature_key` (via [`features.id`](http://features.id)).
               2. **If no record found in `saas_plan_features`:** The feature is NOT part of the plan. Access denied.
               3. **If record found:** Check `saas_plan_features.is_enabled`.
                  1. If `FALSE`: Feature is explicitly disabled for this plan. Access denied.
                  2. If `TRUE`: Feature is principally enabled. Proceed to check limits.
         4. **Check Feature Limits (if quantifiable feature):**
            1. Retrieve the `features.default_limit_value` and `features.default_limit_unit` for the `feature_key`.
            2. Retrieve the `saas_plan_features.limit_value` (override) for this plan and feature.
            3. The effective limit is `saas_plan_features.limit_value` if NOT NULL, otherwise `features.default_limit_value`.
            4. If the feature has an effective limit (e.g., max users, max locations, API calls):
               1. Query the relevant application tables to get the company's current usage of that resource (e.g., `COUNT(*)` from `company_memberships` where `status='active'` for `feature_key='MAX_USERS'`).
               2. If current usage \>= effective limit, and the user is attempting an action that would exceed it (e.g., inviting a new user when at user limit): Access/Action denied. Prompt with "Limit reached. Please upgrade your plan."
         5. **Check Feature-Specific Configuration (if applicable):**
            1. Retrieve `saas_plan_features.configuration` (JSONB).
            2. The specific service/logic handling the feature might use this configuration to further modify behavior (e.g., an API feature might have different rate limits configured here).
         6. **Grant or Deny Access:**
            1. If all checks pass: Access granted / Action allowed.
            2. If any check fails: Access denied / Action disallowed. Return appropriate error/status to client.
      5. **Post-conditions / Outputs:**
         1. User is either allowed to proceed with the action/feature access or is blocked with an appropriate message/UI state.
      6. **Error Handling / Exceptional Flows:**
         1. `company_saas_subscriptions` record not found for the company (should not happen for an active company).
         2. `saas_plans` or `features` records misconfigured.
      7. **Permissions / Authorization Notes:**
         1. This logic is fundamental to the authorization layer of the application, working in conjunction with role-based permissions. A user might have the _role_ to do something, but their company's _plan_ might not include the _feature_.

   9. #### **Workflow: (Company Admin) Cancel Subscription**

      1. **Trigger / Entry Point:**
         1. Company admin navigates to "Subscription Management" / "Billing" section.
         2. Admin clicks "Cancel Subscription."
      2. **Pre-conditions / Required Inputs (from Company Admin):**
         1. Authenticated company admin.
         2. (Optional) Reason for cancellation.
      3. **User Interface Considerations (Functional):**
         1. Confirmation prompt: "Are you sure you want to cancel your \[Plan Name\] subscription? Your access will continue until \[current_billing_period_ends_at\]. You may be downgraded to the Free Tier afterwards."
         2. Optional field for cancellation reason (survey).
         3. Option to "Undo Cancellation" if `status` is `pending_cancellation`.
      4. **Step-by-Step Logic & Rules:**
         1. **Admin confirms cancellation.**
         2. **Retrieve Current Subscription:** Fetch `company_saas_subscriptions` record for the company.
         3. **Handle Based on Current Status:**
            1. If `status` is `'trialing'`:
               1. UPDATE `company_saas_subscriptions` SET `status = 'cancelled'`, `cancellation_requested_at = now()`, `cancellation_effective_at = now()`, `cancellation_reason = [reason]`, `trial_ends_at = now()`. Trial ends immediately. Consider downgrade to free tier if applicable.
            2. If `status` is `'active'` (and it's a paid plan):
               1. UPDATE `company_saas_subscriptions` SET `status = 'pending_cancellation'`, `cancellation_requested_at = now()`, `cancellation_effective_at = current_billing_period_ends_at`, `cancellation_reason = [reason]`.
               2. Inform user that access continues until `cancellation_effective_at`.
            3. If `status` is `'free_tier_active'` or other non-paid active state:
               1. UPDATE `company_saas_subscriptions` SET `status = 'cancelled'`, `cancellation_requested_at = now()`, `cancellation_effective_at = now()`.
         4. **Automated Task (at `cancellation_effective_at` for 'pending_cancellation' status):**
            1. A scheduled task checks for subscriptions where `status = 'pending_cancellation'` AND `cancellation_effective_at <= CURRENT_DATE`.
            2. For each such subscription:
               1. Retrieve the original `saas_plan_id` and its `downgrades_to_plan_id`.
               2. If `downgrades_to_plan_id` exists:
                  1. UPDATE `company_saas_subscriptions` SET `saas_plan_id = [downgrades_to_plan_id]`, `status = 'free_tier_active'` (or `'active'`), clear billing cycle dates, `updated_at = now()`.
                  2. Send "Subscription Cancelled \- Account Downgraded" notification.
               3. Else (no downgrade path):
                  1. UPDATE `company_saas_subscriptions` SET `status = 'cancelled'`, `updated_at = now()`.
                  2. Send "Subscription Cancelled \- Account Access Limited" notification.
         5. **(Optional) Send Cancellation Acknowledgement Email.**
      5. **Post-conditions / Outputs:**
         1. `company_saas_subscriptions.status` is updated to `'pending_cancellation'` or directly to `'cancelled'` / `'free_tier_active'`.
         2. Relevant dates (`cancellation_requested_at`, `cancellation_effective_at`) are set.
      6. **Error Handling / Exceptional Flows:**
         1. Subscription not found or already cancelled.
      7. **Permissions / Authorization Notes:**
         1. Requires company admin role.

   10. #### **Workflow: (Platform Admin) Manually Adjust Company Subscription/Billing**

       1. **Trigger / Entry Point:**
          1. Hyper M v2 Platform Administrator/Support/Sales receives a request or needs to apply a special condition to a specific company's SaaS subscription (e.g., applying a discount coupon, granting a custom trial extension, switching to a non-public plan, applying a one-time credit).
          2. Admin accesses an internal "Company Subscription Management" tool.
       2. **Pre-conditions / Required Inputs (for Platform Admin):**
          1. `company_id` of the target company.
          2. Details of the adjustment to be made:
             1. New `saas_plan_id` (if changing plan).
          3. Custom `price_per_interval_exclusive_vat` (if applying a discount not tied to a standard plan).
          4. New `trial_ends_at` (if extending trial).
          5. New `current_billing_period_ends_at` or `next_billing_date` (if adjusting billing cycle).
          6. One-time credit amount and currency.
          7. Reason/justification for the manual adjustment (for audit purposes).
       3. **User Interface Considerations (Functional \- Internal Admin Tool):**
          1. Search for company by ID or name.
          2. Display current `company_saas_subscriptions` details.
          3. Fields to override/set: `saas_plan_id`, specific price, trial end date, next billing date.
          4. Option to apply a "one-time credit" to the company's account (which might offset future billings).
          5. Mandatory field for "Reason for Adjustment/Audit Note."
       4. 3.10.4. **Step-by-Step Logic & Rules:**
          1. **Platform Admin authenticates and accesses the internal tool.**
          2. **Admin locates the target `company_id` and its subscription.**
          3. **Admin inputs the desired adjustments and reason.**
          4. **System Validation (Internal Tool):**
             1. Validate FKs if `saas_plan_id` is changed.
             2. Ensure dates are logical (e.g., `trial_ends_at` \> `now()`).
             3. If overriding price, ensure currency is consistent or handled.
          5. **Apply Adjustments to `company_saas_subscriptions`:**
             1. UPDATE the `public.company_saas_subscriptions` record for the `company_id`.
             2. Set fields as specified by the admin (e.g., `saas_plan_id`, `trial_ends_at`, `next_billing_date`).
             3. If a custom price is applied that doesn't match a standard plan's price, this might be stored in `company_saas_subscriptions.metadata` (e.g., `{"custom_price_override": 79.99, "original_plan_price": 99.99}`) or a dedicated field if frequent. The `saas_plan_id` would still reflect the _feature set_ they are on. The billing engine would then need to check for this override. _Simpler approach: Create a hidden, non-public `saas_plans` record for such custom deals._
             4. If a one-time credit is applied: This might be logged in a separate `saas_account_credits` table (linking to `company_id`, amount, reason, applied_by_admin_id). The renewal process (Workflow 3.7) would then check for available credits before charging.
             5. Crucially, update `company_saas_subscriptions.notes` or a dedicated audit log with the `reason_for_adjustment` and `admin_id` who performed it.
          6. **(If Price/Plan impacting recurring billing) Synchronize with Payment Gateway (if applicable):**
             1. If the recurring price or plan changes for a credit card subscription, the platform admin might need to manually update the subscription details in the payment gateway's portal, or an API call might be triggered if Hyper M has deep gateway integration for subscription management. This is highly dependent on the payment gateway.
          7. **Send Notification Email to Company Admin:** Inform them of the adjustment made to their subscription (e.g., "Your trial has been extended," "A discount has been applied to your subscription").
       5. **Post-conditions / Outputs:**
          1. The `company_saas_subscriptions` record is updated.
          2. Audit trail (notes/log) of the manual adjustment exists.
          3. Company admin is notified.
          4. Payment gateway subscription may be updated.
       6. **Error Handling / Exceptional Flows:**
          1. Company not found.
          2. Invalid adjustment parameters.
          3. Errors updating database or payment gateway.
       7. **Permissions / Authorization Notes:**
          1. Requires high-level Hyper M v2 Platform Administrator/Support Lead privileges.

   11. #### **Workflow: (Platform Admin) Handling SaaS Subscription Refunds**

       1. **Trigger / Entry Point:**
          1. A company admin requests a refund for a SaaS subscription payment.
          2. Platform Admin/Support verifies the validity of the refund request based on Hyper M v2 refund policy (e.g., within X days of charge, service outage, accidental charge).
       2. **Pre-conditions / Required Inputs (for Platform Admin):**
          1. `company_id`.
          2. Identification of the specific payment to be refunded (e.g., payment transaction ID from gateway, date of charge).
          3. Refund amount (full or partial).
          4. Reason for refund.
       3. **User Interface Considerations (Functional \- Internal Admin Tool):**
          1. Ability to view a company's payment history (from a `saas_payments` table or payment gateway logs).
          2. Option to "Issue Refund" against a specific payment.
          3. Fields for refund amount, reason, and notes.
       4. **Step-by-Step Logic & Rules:**
          1. **Platform Admin verifies refund eligibility and details.**
          2. **Identify Original Payment Method:**
             1. Determine if the original payment was via Credit Card or Bank Wire Transfer.
          3. **Process Refund:**
             1. **If Original Payment via Credit Card (Payment Gateway):**
                1. Platform Admin uses the Payment Gateway's portal or an integrated API function to issue a refund against the specific transaction ID.
                2. The gateway handles returning funds to the customer's card.
                3. Obtain a refund transaction ID from the gateway.
             2. **If Original Payment via Bank Wire Transfer:**
                1. This is a manual financial process. The Hyper M v2 Finance team initiates an outgoing bank transfer to the company's bank account.
                2. This process is external to the application's direct control but needs to be logged.
          4. **Log the Refund in Hyper M v2 System:**
             1. Record the refund in a `saas_refunds` table (or similar, linked to `company_id`, original payment ID, refund amount, refund date, reason, processed_by_admin_id, gateway_refund_tx_id if applicable).
             2. **Adjust Company Subscription Status/Billing (if necessary):**
                1. Does the refund imply a cancellation or change in the subscription period?
                2. **Full Refund for Current Period:** May involve:
                   1. Setting `company_saas_subscriptions.status` to `'cancelled'` or downgrading them (e.g., to `'free_tier_active'`).
                   2. Adjusting `current_billing_period_ends_at` to `now()` or the start of the refunded period.
                   3. Cancelling any corresponding recurring subscription in the payment gateway if applicable.
                3. **Partial Refund:** May not change subscription status but is logged as a financial adjustment.
                4. The exact impact on `company_saas_subscriptions` depends on the reason for the refund and business policy.
             3. **Send Refund Confirmation Email:** Notify the company admin that the refund has been processed.
       5. **Post-conditions / Outputs:**
          1. Refund processed via payment gateway or manual bank transfer.
          2. Refund transaction is logged within Hyper M v2.
          3. `company_saas_subscriptions` record may be updated.
          4. Company admin is notified.
       6. **Error Handling / Exceptional Flows:**
          1. Refund declined by payment gateway (e.g., original transaction too old, insufficient funds in merchant account).
          2. Original payment transaction not found.
          3. Mistakes in manual bank wire details.
       7. **Permissions / Authorization Notes:**
          1. Requires Hyper M v2 Platform Finance/Support Lead privileges with access to payment gateway and refund processing tools.

2. ### **Specific Calculations & Algorithms (If Applicable)**

   1. #### **Trial End Date Calculation:**

      1. **Algorithm:** `trial_ends_at = trial_started_at + (saas_plans.trial_days_offered || ' days')::interval`.
      2. **Purpose:** To accurately determine the end date of a company's trial period based on the start date and the number of trial days specified in their SaaS plan.

   2. **Next Billing Date & Billing Period Calculation:**
      1. **Algorithm (Simplified for fixed intervals):**
         1. `current_billing_period_ends_at = current_billing_period_starts_at + (saas_plans.billing_interval_months || ' months')::interval - '1 day'::interval` (or equivalent date math to correctly land on the last day of the period).
         2. `next_billing_date = (new)current_billing_period_ends_at + '1 day'::interval`.
      2. **Purpose:** To accurately calculate the start and end of billing periods and determine the subsequent renewal date. More complex logic would be needed for anniversary billing that aligns to specific day-of-month, or for handling varying month lengths precisely if "exactly X months" is critical.
   3. **Feature Access Determination Logic (Conceptual):**
      1. **Algorithm Steps:**
         1. Retrieve `company_saas_subscriptions` for the active `company_id` to get `current_saas_plan_id` and `status`.
      2. If `status` is not permissive (e.g., `'active'`, `'trialing'` for trial-included features, `'free_tier_active'` for free-tier-included features), deny access (or apply status-specific restrictions).
      3. Query `public.saas_plan_features` to find the entry for `current_saas_plan_id` and the requested `feature_key`.
      4. If no entry or `is_enabled = FALSE`, deny access.
      5. If quantifiable feature (check `features.default_limit_unit`):
         1. Determine effective limit: `saas_plan_features.limit_value` (if set) OR `features.default_limit_value`.
         2. Query current company usage of the limited resource.
         3. If `current_usage >= effective_limit` AND action would exceed limit, deny action.
      6. Apply `saas_plan_features.configuration` if present.
      7. If all checks pass, grant access.

**Purpose:** To enforce feature gating based on the company's active plan, feature enablement, usage limits, and specific configurations.

4. **Pro-ration Calculation for Plan Changes (If Implemented \- Currently Assumed Change at End of Period):**
   1. _This section would be detailed if immediate pro-rated upgrades/downgrades were a core requirement. It would involve:_
      1. Calculating days remaining in the current billing cycle.  
         2. Calculating the daily rate of the old plan and the new plan.  
         3. Calculating the cost of the new plan for the remaining days.  
         4. Calculating the unused credit from the old plan for the remaining days.  
         5. Netting these amounts to determine an immediate charge or credit.

**Purpose:** To fairly charge or credit companies when they change plans mid-billing cycle.

_Current BLA primarily assumes changes happen at the end of the current billing cycle to simplify this._

5. **Discount/Coupon Application Logic (If implemented systematically):**
   1. _If discount codes are supported:_
      1. Algorithm to validate coupon code (existence, expiry, applicability to plan/customer).  
         2. Calculation of discounted price (percentage off, fixed amount off first period, fixed amount off recurring).

**Purpose:** To allow for promotional pricing.  
_Current BLA primarily handles discounts via manual adjustments by platform admins._

5. ### **Integration Points**

   1. #### **Internal Hyper M v2 Modules:**

      1. **Database (`public` schema):** Direct CRUD operations on `saas_plans`, `features`, `saas_plan_features`, `company_saas_subscriptions`. Reads from `companies`, `users`, `currencies`.
      2. **User Authentication & Onboarding Module:** The "Initial Company Onboarding" workflow in that BLA triggers the "Initial Company Trial Onboarding" (Workflow 3.3) of this BLA.
      3. **Company & User Management Module:** Workflows like "Invite New User" or "Create New Company Location" in that BLA will need to integrate with the Feature Gating logic (Workflow 3.8) of this BLA to check against plan limits (e.g., max users, max locations).
      4. **All other application modules:** Any module providing distinct features will be subject to the Feature Gating logic (Workflow 3.8) defined herein. The frontend and backend services for these modules will query feature access rights.

   2. #### **External Services:**

      1. ##### **Payment Gateway (e.g., Stripe, Braintree, PayPal):**

         1. Integration for processing one-time and recurring credit card payments (Workflow 3.5, 3.7).
         2. Securely handling payment method tokenization.
         3. Processing refunds (Workflow 3.11).
         4. Potentially managing subscription objects directly within the gateway if its subscription management features are heavily used.

      2. ##### **Email Service (e.g., SendGrid, AWS SES):**

         1. Sending trial expiry notifications (Workflow 3.4).
         2. Sending payment success/failure/receipt emails (Workflow 3.5, 3.7).
         3. Sending plan change/activation/cancellation/downgrade confirmations (Workflow 3.5, 3.6, 3.7, 3.9, 3.10, 3.11).

      3. ##### **Scheduled Job Runner / Cron Service (e.g., pg_cron, Kubernetes CronJob, dedicated scheduler):**

         1. Executing automated tasks for trial expiry management, pre-renewal notifications, recurring payment processing, and processing cancellations effective at period end (Workflow 3.4, 3.7, 3.9).

      4. ##### **Banking System (Indirect):**

         1. For Bank Wire Transfer payments, Hyper M v2 finance team reconciles bank statements and uses an internal tool to trigger activation (Workflow 3.6).
         2. For Bank Wire Refunds, Finance team initiates transfers manually (Workflow 3.11).

6. ### **Data Integrity & Constraints (Beyond DDL)**

   1. **Single Active Subscription Per Company:** Application logic must ensure that the `UNIQUE` constraint on `company_saas_subscriptions.company_id` is maintained, meaning a company cannot have multiple overlapping subscription records. Plan changes update the existing record.
   2. **Plan & Feature Consistency:** Platform admin tools should prevent linking features to plans in a way that creates logical impossibilities (e.g., enabling a "Max 5 Users" feature limit while also enabling a "Max 50 Users" feature limit on the same plan; the more restrictive or specific one should take precedence, or such conflicts prevented at definition).
   3. **Payment Gateway Synchronization:** For recurring CC payments, if the subscription price or interval changes in Hyper M v2, the corresponding subscription object in the payment gateway must be updated to ensure correct future billing. Failure to do so can lead to billing discrepancies. (This is a critical operational point).
   4. **Trial Logic:** A company should typically only receive one initial trial for a given major plan level. Logic should prevent re-trialing the same plan repeatedly without manual admin intervention.
   5. **Downgrade Path Logic:** If a `saas_plans.downgrades_to_plan_id` is set, ensure this target plan is active and appropriate (e.g., usually a free tier or a very basic plan).
   6. **Feature Limit Enforcement:** The application logic across all modules must consistently call the feature gating mechanism (Workflow 3.8) before allowing actions that consume limited resources to prevent exceeding plan quotas.

7. ### **Reporting Considerations (High-Level) (Primarily for Hyper M v2 Platform Administrators)**

   1. #### **Key SaaS Metrics:**

      1. Monthly Recurring Revenue (MRR) / Annual Recurring Revenue (ARR).
      2. Customer Churn Rate (number of cancellations / downgrades from paid).
      3. Trial Conversion Rate (trials to paid subscriptions).
      4. Customer Lifetime Value (CLTV).
      5. Average Revenue Per Account (ARPA).

   2. #### **Subscription Data:**

      1. Distribution of companies across different `saas_plans`.
      2. Number of active trials, active paid subscriptions, past_due accounts.
      3. Subscription upgrade/downgrade trends.

   3. #### **Payment Data:**

      1. Successful vs. Failed payment transaction logs.
      2. Revenue by payment method.
      3. Refund rates and reasons.

   4. #### **Feature Usage & Adoption:**

      1. (If detailed feature usage tracking is implemented beyond simple gating) Popularity of specific features across different plans.
      2. Usage of limited resources against plan quotas (to identify upsell opportunities or plan fit issues).

   5. #### **CE & EE Metrics (if discernible):**

      1. Number of active CE instances (if telemetry or voluntary registration exists).
      2. Number of EE licenses sold/active.

8. ### **Open Questions / Future Considerations for this BLA**

   1. **Detailed Dunning Strategy:** Specific email sequences, retry logic for failed payments (e.g., Smart Retries via gateway), and precise timelines before downgrade/cancellation.
   2. **Automated Pro-ration for Plan Changes:** Implementing complex calculations for immediate, pro-rated billing adjustments upon plan upgrades/downgrades.
   3. **Coupon/Discount Code System:** A full system for creating, managing, and applying discount codes during checkout or by admins.
   4. **"Grandfathering" Policies:** Detailed rules for how existing subscribers are handled when a plan they are on is changed or deactivated by platform admins.
   5. **Usage-Based Billing Features:** For features where billing is not just flat-rate per plan but based on consumption (e.g., per API call above a certain threshold, per GB of storage used beyond plan allowance). This would require significant additions for metering and billing.
   6. **EE/CE Licensing & Activation:** Specific workflows for generating, distributing, and validating license keys for Enterprise Self-Hosted and potentially feature-unlocked Community Editions. This would likely be its own BLA.
   7. **Payment Method Management by Company Admin:** UI for company admins to add/update/remove their credit card details securely.
   8. **Tax Calculation & Compliance for SaaS Fees:** Detailed integration with tax calculation services (e.g., Avalara, TaxJar) or robust internal logic for applying correct VAT/sales tax to Hyper M v2's own subscription fees based on the tenant company's location and tax status. (This is a major topic itself).
   9. **Affiliate/Referral Program Integration:** If Hyper M v2 plans to have an affiliate program, how commissions and tracking integrate with subscriptions.
   10. **Historical Subscription Changes Log:** A dedicated table to log every change to a `company_saas_subscriptions` record (plan change, status change, billing date change) for audit and historical analysis beyond the `updated_at` timestamp.
   11. **Advanced Feature Configuration:** For features with complex settings (beyond simple limits or on/off) that vary by plan, how these configurations are structured in `saas_plan_features.configuration` and managed by platform admins.
