# **Hyper M v2: Master Blueprint (Version 1.0.7 \- Consolidated)**

## **_Project Name: Hyper M v2_**

## **I. Core Business Logic (v1.0.5 Base)**

- **Purpose:** Our SaaS platform aims to streamline and centralize core business operations for small to medium-sized enterprises (SMEs).
- **Key Functionality:** It provides tools for managing:
  - **Customer & Partner Relationships:** Tracking interactions, agreements, and contact details for customers, suppliers, and other business partners.
  - **Product & Service Catalog:** A comprehensive repository of all products and services offered, including pricing, descriptions, and stock levels.
  - **Inventory Management:** Real-time tracking of product stock across multiple warehouse locations, facilitating accurate order fulfillment and stock control.
  - **Invoicing & Billing:** Creation, tracking, and management of sales invoices, credit notes, debit notes, including support for recurring subscriptions and payment tracking.
  - **Sales & Procurement:** Managing sales orders, purchase orders, and goods receipts.
  - **Fiscalization:** Handling fiscal receipts according to local regulations.
  - **User & Role Management:** Secure access control allowing different team members within a company to perform specific tasks based on their assigned roles.
- **Core Value Proposition:** To enhance operational efficiency, reduce manual errors, provide actionable insights into business performance, and foster better collaboration within organizations.

## **II. User Roles & Permissions (v1.0.5 Base)**

- **General Principle:** Permissions will be granular and tied to specific module actions (e.g., `partners.create`, `invoices.view_all`). User roles are defined **per company context**.
- **Multi-Tenancy Model:**
  - A single global **User** can be a member of **multiple Companies**.
  - A **User** can be a Manager/Admin in one Company, and a regular user (e.g., Sales Rep) in another.
  - A **User** can create multiple Companies and manage them.
- **Role Management:** Roles will be managed via a `roles` table in the database. Hasura's Row-Level Security (RLS) will be the primary mechanism for enforcing permissions based on the user's assigned role within the _currently selected company_.
- **Defined Roles (Examples):**
  - **Admin:** Full system access within a specific Company, company-wide settings, user management (add/remove users, assign roles), module configuration.
  - **Manager:** Oversight over specific departments/modules within a specific Company. Can view all data within their assigned modules, perform CRUD operations on entities, and approve/reject certain workflows.
  - **Sales Rep:** Create and manage Partners, create Sales Orders, view Product catalog and inventory levels within a specific Company. Limited modification of system-wide settings or user management.
  - **Warehouse Staff:** Manage Inventory (stock levels, movements, transfers), process Goods Receipts, fulfill orders, receive goods, view Product details within a specific Company. Limited or no access to financial or customer data.

## **III. Tech Stack Decision (v1.0.5 Base \- with minor clarifications)**

- **Frontend:** Angular (Latest Stable Version)
  - **Framework:** Single Page Application (SPA) with **Server-Side Rendering (SSR)** for improved performance and SEO.
  - **UI Library:** Material Design for consistent UI/UX.
  - **SSR Server:** Node.js/Express will be used as the server runtime for Angular SSR, primarily responsible for pre-rendering and serving the Angular application. This server will **not** serve as a primary backend API for core business logic.
- **Backend & API:**
  - **Core API Gateway/GraphQL Engine:** **Hasura GraphQL Engine (DDN / v3)** \- This is the central hub for all data access and GraphQL operations, offering realtime capabilities and robust authorization via JWT.
  - **Data Connectors (Hasura DDN):** Custom business logic that directly interacts with data sources or requires complex GraphQL resolution will be implemented as **Hasura Connectors** (e.g., in TypeScript/Node.js). These connectors extend Hasura's GraphQL API seamlessly.
  - **Dedicated Node.js Services:** For specific backend functionalities that are not directly exposed as GraphQL within Hasura's data graph:
    - **Authentication Service:** A dedicated Node.js/Express service for user registration, login, JWT issuance, and password management.
    - **Webhooks & Event Processors:** Node.js/Express endpoints or serverless functions to receive and process events triggered by Hasura (e.g., sending emails, external service integrations, background tasks).
    - **File Handling:** Potentially a small Node.js service for managing file uploads/downloads (e.g., generating pre-signed URLs for cloud storage).
    - **Fiscal Device Integration Service:** A dedicated service to handle communication with fiscal printer APIs.
- **Database:** PostgreSQL
  - **Type:** Relational Database Management System (RDBMS).
  - **Schema:** Managed directly through DDL scripts (as defined in this blueprint) and migrations.

## **IV. Global System Principles & Data Handling (V2 Update)**

- **UI/UX Consistency:** Adhere strictly to Material Design principles for all UI components, spacing, typography, and color palettes. The application must be fully responsive and optimized for common desktop and tablet resolutions.
- **Forms:** All forms must be built using Angular Reactive Forms. Client-side validation is mandatory, with clear, user-friendly error messages. Form submissions should provide appropriate loading states and success/error feedback.
- **Data Handling & Formats:**
  - **Currency & Monetary Values:** **All monetary values will be stored and handled as `NUMERIC(15, 5)`**. This precision is critical for handling diverse currencies, exchange rates, complex VAT calculations, and B2B financial accuracy. The principle of storing values as "cents" (integers) has been abandoned for V2 due to these complexities.
  - **Dates & Times:** All dates and times are stored and transmitted in **UTC** format (`TIMESTAMP WITH TIME ZONE` or `DATE` where appropriate). Frontend will convert to local timezones for display.
  - **Identifiers:** All primary keys for main business entities will be **UUIDs** (`DEFAULT gen_random_uuid()`) for distributed system compatibility and reduced collision risk.
  - **Translations:** User-facing text in multi-lingual entities will be handled via associated `_translations` tables, using a `translation JSONB` column to store key-value pairs for different locales.
- **API Interactions:**
  - Prioritize GraphQL queries and mutations via Hasura for all data operations.
  - Use custom Node.js services with REST or other protocols for specific integrations (e.g., fiscal printers, payment gateways), complex workflows, or third-party webhooks where GraphQL is not the ideal fit.
- **Error Handling:** Implement consistent error structures for API responses and provide clear, actionable, user-friendly error messages on the frontend.
- **Authentication & Authorization:**
  - Leverage JWT tokens for user authentication (global user identity).
  - Hasura's permission system will be the primary mechanism for fine-grained row-level and column-level authorization based on `X-Hasura-User-ID`, `X-Hasura-Role` (from JWT claims), and **`X-Hasura-Company-ID` (sent via HTTP header for current company context).**
- **Multi-Tenancy Context Management:**
  - The _currently selected `Company ID`_ will be managed client-side and sent via the `X-Hasura-Company-ID` header.
  - All backend logic (Hasura RLS, custom services) will filter data and enforce permissions based on this provided `X-Hasura-Company-ID` and the user's role within that company.
- **Document Numbering:** A centralized, configurable system (`document_sequence_definitions` table and `get_next_document_number()` function) will manage sequential document numbers, scoped by `company_location_id` and `sequence_type_key`. Fiscal documents (invoices, credit/debit notes) share a sequence.
- **Data Immutability for Financial Records:** Once a financial document (invoice, credit/debit note, fiscal receipt) is finalized/issued, its core financial data (items, prices, quantities, VAT) is considered immutable. Corrections are made via new documents (e.g., credit/debit notes). Snapshots of key related data (e.g., `partner_details`, `shipping_address_details`) are stored on transactional documents.
- **VAT Handling:** The system will support complex VAT determination (domestic, EU B2B/B2C, VIES, OSS, export, reverse charge). The `invoice_items.applied_vat_rule_id` is the authoritative record for VAT applied per line. Invoice headers provide summaries.
- **Performance:** Aim for fast loading times and efficient data retrieval. Optimize GraphQL queries, use appropriate indexing, and implement lazy loading for Angular modules.
- **Naming Conventions:** Adhere to common Angular, Node, Postgres (snake_case for tables/columns), and GraphQL naming conventions.

## **V. Database Schema (DDL)**

All Data Definition Language (DDL) statements that define the database schema for Hyper M v2 are consolidated into a single, master SQL file. This file serves as the definitive source of truth for the database structure.

**Master DDL File:** `HyperM_V2_Schema_Consolidated_v1.0.7.sql`

This consolidated SQL file is organized into the following major sections, corresponding to the system's core modules and foundational elements:

1. ### **Core Foundation Entities:**

   1. Defines foundational tables for users, global roles, companies, company memberships, company types, company locations, and associated translations. Also includes global lookups like locales, countries, currencies, basic partner structures, and initial VAT-related tables (fiscal VAT groups, VIES responses).
   2. _Key Tables:_ `public.roles`, `public.users`, `public.company_membership_status_enum`, `public.company_memberships`, `public.company_types`, `public.companies`, `public.company_translations`, `public.company_locations`, `public.company_location_translations`, `public.company_user_operator_status_enum`, `public.company_user_operators`, `public.locales`, `public.countries`, `public.country_translations`, `public.partner_type_enum`, `public.partners`, `public.partner_translations`, `public.currencies`, `public.company_currency_settings`, `public.currency_rates`, `public.fiscal_vat_groups`, `public.vat_responses`.

2. ### **Nomenclatures & Product Catalog Module:**

   1. Defines tables for managing the product and service catalog, including nomenclature types, units of measure, the core nomenclatures table with attributes like pricing and inventory tracking behavior, and associated translations.
   2. _Key Tables:_ `public.inventory_tracking_type_enum`, `public.nomenclature_types`, `public.nomenclature_unit`, `public.nomenclatures`, `public.nomenclature_translations`.

3. ### **Document Numbering System:**

   1. Defines the centralized system for generating formatted, sequential document numbers, including the sequence definitions table and the PL/pgSQL function for number generation.
   2. _Key Tables & Functions:_ `public.document_sequence_definitions`, `public.get_next_document_number()`.

4. ### **Subscriptions Module (Tenant-Facing):**

   1. Defines tables for managing recurring subscription contracts that tenant companies offer to their own partners/customers.
   2. _Key Tables:_ `public.subscription_status_enum`, `public.subscriptions`.

5. ### **Sales & Ordering Module:**

   1. Defines tables for managing sales orders and their line items, including status tracking and provisional financial details.
   2. _Key Tables:_ `public.sales_order_status_enum`, `public.order_item_fulfillment_status_enum`, `public.sales_orders`, `public.sales_order_items`.

6. ### **Invoicing & Financial Documents Module:**

   1. Defines tables for creating and managing invoices, credit notes, debit notes, and related lookup tables like payment methods, payment terms, and detailed VAT rules.
   2. _Key Tables:_ `public.invoice_status_enum`, `public.invoice_vat_summary_enum`, `public.payment_methods`, `public.payment_terms`, `public.vat_rules_and_exemptions`, `public.invoices`, `public.invoice_items`, `public.credit_notes`, `public.credit_note_items`, `public.debit_notes`, `public.debit_note_items`.

7. ### **Fiscalization Module:**

   1. Defines tables for recording information from fiscal receipts generated by fiscal devices, linking them to source transactions.
   2. _Key Tables:_ `public.fiscal_receipt_status_enum`, `public.fiscal_receipts`, `public.fiscal_receipt_items`.

8. ### **Procurement & Purchasing Module:**

   1. Defines tables for managing purchase orders issued by tenant companies to their suppliers.
   2. _Key Tables:_ `public.purchase_order_status_enum`, `public.purchase_orders`, `public.purchase_order_items`.

9. ### **Inventory Management Module:**

   1. Defines tables for managing inventory storage locations, goods receipts, individual stock items (including batch/serial tracking and costing), stock allocations to demand, and a comprehensive stock movement audit log.
   2. _Key Tables:_ `public.storage_status_enum`, `public.storage_type_enum`, `public.grn_status_enum`, `public.inventory_stock_item_status_enum`, `public.stock_allocation_status_enum`, `public.stock_movement_type_enum`, `public.storages`, `public.storage_permission_types`, `public.user_storage_permissions`, `public.goods_receipt_notes`, `public.goods_receipt_note_items`, `public.inventory_stock_items`, `public.stock_allocations`, `public.stock_movements_log`.

10. ### **SaaS Platform Management Module (For Hyper M v2 Itself):**

    1. Defines the structure for managing SaaS subscription plans offered by Hyper M v2, features, feature gating, and tenant company subscriptions to the Hyper M v2 platform itself.
    2. _Key Tables:_ `public.saas_plan_type_enum`, `public.saas_feature_status_enum`, `public.company_saas_subscription_status_enum`, `public.saas_plans`, `public.features`, `public.saas_plan_features`, `public.company_saas_subscriptions`.

_(Developers should refer directly to the `HyperM_V2_Schema_Consolidated_v1.0.7.sql` file for the complete and authoritative DDL specifications.)_

## **VI. Key Architectural Decisions & V2 Principles Summary (Consolidated)**

1. **Monetary Values:** All monetary figures are stored as `NUMERIC(15, 5)` to ensure precision for multi-currency transactions, VAT, and B2B requirements.
2. **Primary Keys:** Standardized on `UUID` for all primary business entities.
3. **Multi-Tenancy:** Data is scoped by `company_id`. Operational documents and sequences are further scoped by `company_location_id`. Access is controlled via `X-Hasura-Company-ID` header and RLS.
4. **Translations:** Implemented using a `_translations` table pattern with a `translation JSONB` column for flexibility.
5. **Document Numbering:** Centralized via `document_sequence_definitions` and `get_next_document_number()`, supporting prefixes, suffixes, padding, shared sequences (e.g., 'FISCAL_DOCUMENTS'), and company location scoping.
6. **Invoice Currency & Legal Compliance (Bulgaria \- ЗДДС Чл. 114, ал. 5):**
   - Invoices can be issued in any transaction currency. All line items (`invoice_items`) are stored in this transaction currency.
   - The `invoices` header stores totals in the transaction currency AND totals converted to the company's default currency (BGN).
   - Crucially, the _taxable base_ (`total_exclusive_vat_company_default`) and _VAT amount_ (`total_vat_amount_company_default`) in BGN **must be displayed on the printed invoice document.**
7. **Fiscal Receipt Currency:** `fiscal_receipts` and `fiscal_receipt_items` are **always in the company's default currency (BGN)** as per Bulgarian fiscalization laws.
8. **POS Transaction Handling:**
   - Managed via `sales_orders` with `order_type_key = 'POS_TRANSACTION'`.
   - These sales orders MUST be in the company's default currency (BGN).
   - Pricing for POS items primarily uses `nomenclatures.default_selling_price_inclusive_vat`.
   - Immediately triggers `fiscal_receipts` generation.
9. **Inventory Tracking Types:** `nomenclatures.inventory_tracking_type` (`none`, `quantity_only`, `batch_tracked`, `serial_tracked`) dictates how `inventory_stock_items` are created, managed, and tracked.
10. **Pricing Hierarchy & Item-Specific Prices:**
    - `nomenclatures` stores _default_ selling prices (inclusive for POS, and exclusive).
    - `inventory_stock_items` (for batch/serial tracked items) can store _item-specific_ selling prices (`selling_price_exclusive_vat`, `selling_price_inclusive_vat`) that override nomenclature defaults and other general pricing rules.
    - The Business Logic for sales orders will define the full price determination hierarchy (item-specific \-\> contract \-\> promotion \-\> nomenclature default \-\> price lists).
11. **Data Snapshots:** Key information (e.g., `partner_details`, `shipping_address_details`) is snapshotted as `JSONB` on transactional documents (`invoices`, `sales_orders`) to ensure historical integrity.
12. **Immutability of Financial Records:** Once finalized, financial documents are immutable. Changes require new offsetting documents (credit/debit notes).
13. **Stock Movement Logging:** A comprehensive `stock_movements_log` captures all changes to `inventory_stock_items`, intended to be populated by database triggers on `inventory_stock_items` initially.

## **VII. Business Logic Addendums (Next Phase \- To Be Defined)**

_(This section will be populated as we define the business logic for each module.)_

1. **Sales & Order Processing (Pre-Invoicing/Pre-Fulfillment) \- NEXT FOCUS**
2. Invoicing, Credit Notes & Debit Notes
3. Subscriptions Management (Billing Cycle, Invoice Generation) \- **version 1 available**
4. Procurement & Purchase Order Management
5. Inventory Management & Goods Receipt
6. Fiscalization & Fiscal Receipts
7. User Management & Company Setup
8. (Other modules as they arise)

## **VIII. Session Resume Context & Next Steps (For AI & User)**

- **My Role (AI):** Re-internalize this consolidated blueprint (v1.0.6). Prepare to assist in defining the "Sales & Order Processing (Pre-Invoicing/Pre-Fulfillment)" Business Logic Addendum. Focus on consistency, clarity, and adherence to established DDLs and principles.
- **Your Role (User):** Prepare to detail the workflows, rules, calculations, and interactions for creating and managing `sales_orders` and `sales_order_items` up to the point of invoicing or fulfillment, including the pricing engine logic and stock allocation concepts.
- **Pending DDLs for Future Consideration (Lower Priority for Immediate Next Session):**
  - `quotes` and `quote_items`
  - `delivery_notes` / `shipments` and `_items`
  - Advanced Inventory: `physical_items` (for extended serial data), `item_batches` (for extended batch data), `stock_adjustments`, `stock_takes`.

## **IX: Project Workflow & Documentation Standards**

### **A. Business Logic Addendum (BLA) \- Prioritized Development Order**

The following order will be used for the collaborative definition and creation of Business Logic Addendums (BLAs). This order prioritizes foundational system functionalities.

1. **BLA: User Authentication & Onboarding** (Covers parts of the "Foundation & Administration Module")
   - _Status: Drafted (Session 2\)_
2. **BLA: Company & User Management** (Covers further parts of the "Foundation & Administration Module")
   - _Status: Drafted (Session 3\)_
3. **BLA: Platform Subscription & Plan Management (for Hyper M v2 itself) & Feature Gating**
   - _Status: Drafted (Session 4 \- Current)_
4. **BLA: Nomenclatures Module (Product & Service Catalog)** (Covers the "Product & Service Catalog Module")
   - _Key Topics:_
     - CRUD operations for `nomenclature_types` (global and company-specific).
     - CRUD operations for `nomenclature_unit` (global and company-specific).
     - CRUD operations for `nomenclatures` (products, services, assets, tenant-defined subscription plans, etc.), including:
       - Management of `item_code`, `name`, `description`, `barcode`.
       - Assignment and implications of `nomenclature_type_id` and `base_unit_id`.
       - Logic and validation related to `inventory_tracking_type` (none, quantity_only, batch_tracked, serial_tracked) and its impact on other modules (especially Inventory).
       - Management of physical attributes (weight, volume, dimensions).
       - Definition and usage of default pricing: `default_selling_price_inclusive_vat`, `default_selling_price_exclusive_vat`, `default_selling_price_currency_id`, `default_selling_price_vat_rule_id`, and `estimated_default_cost_price`. How these serve as fallbacks.
       - Definition and usage of `default_vat_rule_id`.
       - Management of default supplier information.
       - Logic for `is_active`, `is_sellable`, `is_purchasable` flags and their interaction with `nomenclature_types` defaults.
       - Management of `main_image_url`, `additional_images` (JSONB), and `custom_attributes` (JSONB).
     - CRUD operations for `nomenclature_translations` and linking to the `Core_Principle_Translations.md`.
     - Validation rules (e.g., `item_code` uniqueness per company, consistency of pricing fields, relationship between `nomenclature_type.is_stockable` and `nomenclatures.inventory_tracking_type`).
     - Interaction points: How nomenclatures are selected and their default data (prices, VAT rules, tracking types) is consumed by Sales, Invoicing, Procurement, Inventory, and Subscriptions (Tenant-Facing) modules.
   - _Status: NEXT TO BE DRAFTED_
5. **BLA: Partners Management (CRM Base)** (Covers the "Partners Module")
   - _Key Topics:_ CRUD for `partners` (customers & suppliers), `partner_type_enum` logic, management of `partner_translations`, integration with VIES for VAT validation.
   - _Status: TO BE DRAFTED_
6. **BLA: Inventory Management & Stock Control** (Covers the "Inventory Management Module")
   - _Status: TO BE DRAFTED_
7. **BLA: Goods Receipt** (Covers the "Goods Receipt Module")
   - _Status: TO BE DRAFTED_
8. **BLA: Procurement & Purchase Order Management** (Covers the "Procurement & Purchasing Module")
   - _Status: TO BE DRAFTED_
9. **BLA: Sales & Order Processing (Pre-Invoicing/Pre-Fulfillment)** (Covers the "Sales & Ordering Module")
   - _Status: TO BE DRAFTED_
10. **BLA: Invoicing, Credit Notes, Debit Notes, & Advance Payments** (Covers the "Invoicing & Financial Documents Module," including logic for single/multiple advance payments and their reconciliation on final invoices).
    - _Status: TO BE DRAFTED_
11. **BLA: Subscriptions Management (Tenant-Facing)** (Covers the "Subscriptions Module" for how tenants bill _their_ customers).
    - _Status: TO BE DRAFTED_
12. **BLA: Fiscalization & Fiscal Receipts** (Covers the "Fiscalization Module")
    - _Status: TO BE DRAFTED_
13. **BLA: Quoting & Proposals** (Covers pre-sales document generation) _(New Placeholder)_
    - _Key Topics:_ CRUD for Quotes and Quote Items; converting Quotes to Offers/Proposals; status lifecycle for quotes. (Requires DDLs for `quotes`, `quote_items`).
    - _Status: TO BE DRAFTED (Later, as it builds on Partners & Nomenclatures)_
14. **BLA: Offers & Proforma Invoices** (Covers advanced pre-sales documents) _(New Placeholder)_
    - _Key Topics:_ CRUD for Offers/Proposals (if distinct from Quotes) and their items; CRUD for Proforma Invoices and their items; converting Offers to Proforma Invoices; linking Proforma Invoices to Sales Orders or direct Invoices (post-Invoicing BLA); handling advance payments against Proforma Invoices (post-Invoicing BLA). (Requires DDLs for `offers`, `offer_items`, `proforma_invoices`, `proforma_invoice_items`).
    - _Status: TO BE DRAFTED (Later, due to dependencies on Invoicing BLA for some functionalities)_
15. **BLA: Service & Job Tracking (for Uninvoiced Items)** (Covers tracking billable work before invoicing) _(New Placeholder)_
    - _Key Topics:_ Mechanisms for logging billable services, time, or goods delivered that are not yet part of a formal sales order but need to be aggregated for periodic invoicing (e.g., monthly service retainers, ad-hoc work). (May require new DDLs for `service_logs`, `billable_items` etc.).
    - _Status: TO BE DRAFTED (Later)_

_(Further BLAs for other modules/enhancements as they arise)_

### **B. Standard Template for Business Logic Addendum (BLA) Documents**

All `BLA_Module_XYZ.md` documents should adhere to the following template structure to ensure consistency and clarity.

---

#### **Business Logic Addendum: \[Module Name\]**

**Document Version:** 1.0 _(Increment as revised)_ **Date:** YYYY-MM-DD **Related DDLs:** \[List core table names from `HyperM_V2_Schema_Consolidated_vX.Y.Z.sql` relevant to this BLA, e.g., `public.users`, `public.companies, public.*_translations (when applicable)`\] **Primary Audience:** Development Team

1. **Overview & Purpose**
   1. Brief description of this module's function and the specific scope of this BLA.
   2. Key objectives the business logic herein aims to achieve.
2. **Core Entities & Their States/Statuses**
   1. For each primary entity managed by this BLA:
      1. Recap of its purpose (1-2 sentences).
      2. Detailed explanation of its status lifecycle (e.g., `users.email_verified` (T/F), `company_memberships.status` ENUM transitions). Clearly define what each status means and what events trigger transitions. Reference DDL ENUMs.
      3. Translations:
         1. Briefly state that the entity supports translations via its \[entity_name\]\_translations table.
         2. Link back to the main Core_Principle_Translations.md document for the general strategy.
         3. Specify WHICH fields of the parent entity are translatable and thus would have corresponding keys in the translation JSONB object. For example, for partners_translations: "Translatable fields include name, legal_responsible_person, address_line1, address_line2, city, region_name."
         4. Outline any specific business logic related to creating/updating these translations within the context of that module's workflows. For instance, when a user edits a Partner and changes its name in the company's default locale, what happens to existing translations? Does the UI provide fields to edit translations directly?
3. **Key Workflows & Processes** _(This is the main section, broken down by specific functionalities/user stories)_
   1. **3.x. Workflow Name (e.g., User Registration Process)**
   2. **3.x.1. Trigger / Entry Point:** (e.g., User navigates to /register page and submits form)
   3. **3.x.2. Pre-conditions / Required Inputs:** (e.g., Valid email, password meeting criteria, first name, last name)
   4. **3.x.3. User Interface Considerations (Functional):** (Key fields involved, expected user interactions – not UI design)
   5. **3.x.4. Step-by-Step Logic & Rules:**
      1. Itemized processing steps from start to finish.
      2. Input validation rules (e.g., email format, password strength, required fields).
      3. Defaulting logic applied.
      4. Calculations performed (if any).
      5. Interactions with other modules/entities (e.g., checking email uniqueness in `users`).
      6. Database Operations (Conceptual: e.g., "INSERT new record into `users` table with status X", "UPDATE `companies` table").
      7. External Service Calls (e.g., "Send email verification link via email service").
   6. **3.x.5. Post-conditions / Outputs:** (e.g., User record created with `email_verified=FALSE`, JWT token issued for session, Welcome email sent)
   7. **3.x.6. Error Handling / Exceptional Flows:** (e.g., Email already exists, invalid input, email service failure)
   8. **3.x.7. Permissions / Authorization Notes:** (e.g., Publicly accessible endpoint for registration)
4. **Specific Calculations & Algorithms (If Applicable)**

   (Detail any complex calculations not fully covered in workflow steps, e.g., complex permission resolution if not purely role-based).

5. **Integration Points**

   How this module (or workflows within) interacts with:

   1. Other internal Hyper M v2 modules (data dependencies, event triggers).  
      2. External services (e.g., Authentication service, Email service).

6. **Data Integrity & Constraints (Beyond DDL)**

   Business rules ensuring data consistency not fully captured by DDL (e.g., "A user creating a company automatically becomes an 'admin' in that company's `company_memberships` table with 'active' status").

7. **Reporting Considerations (High-Level)**

   Key data points from this module/workflow crucial for operational or business intelligence reports.

8. **Open Questions / Future Considerations for this BLA**

   Points needing further clarification or deferred enhancements related to this BLA's scope.

### **C. "Functional & Navigational Map" Document Structure**

**Hyper M v2 \- Functional & Navigational Map**

1. **Introduction**
   1. **Purpose of This Document:** This document serves as the high-level, bird's-eye view and primary navigational guide for all project artifacts related to the Hyper M v2 SaaS platform. Its goal is to help users (primarily the development team) quickly understand the overall system structure, core modules, key principles, and locate detailed documentation for specific areas. It is designed to remain concise, with all in-depth information residing in linked, separate files.
   2. **How to Use This Map:** Use this map to get an overview of a module or core principle. Follow the provided links to access detailed DDL (Data Definition Language) specifications, Business Logic Addendums (BLAs), principle explanations, and other relevant artifacts.
   3. **Master Artifacts:**
      1. **Master DDL File:** HyperM_V2_Schema_Consolidated_vX.Y.Z.sql (This file is the single source of truth for all database schema definitions. Sections within this file correspond to the modules listed below.)
      2. **This Navigational Map:** The document you are currently reading.  

2. **Core System Principles** _(Brief one-liner summaries linking to detailed standalone files for each principle)_

   1. **Authentication and Security:** JWT generation, rotation and handling. \-\> \[Link to: Core_Principle_AuthenticationSecurity.md\]
   2. **Multi-Tenancy:** Each company is an isolated tenant; users have roles per company. \-\> \[Link to: Core_Principle_MultiTenancy.md\]
   3. **Currency Handling:** Supports transaction currency and company default (BGN); specific BGN display rules for invoices/fiscal docs. \-\> \[Link to: Core_Principle_Currency.md\]
   4. **VAT Logic:** System for defining and applying VAT rules, including handling of Advance Payments. \-\> \[Link to: Core_Principle_VAT.md\]
   5. **Document Numbering:** Centralized, configurable, sequential numbering for documents. \-\> \[Link to: Core_Principle_DocNumbering.md\]
   6. **Data Immutability:** Finalized financial records are immutable; changes via new offsetting documents. \-\> \[Link to: Core_Principle_DataImmutability.md\]
   7. **Translations:** User-facing text via \_translations tables with JSONB. \-\> \[Link to: Core_Principle_Translations.md\]
   8. **Key Data Formats:** Standards for monetary (NUMERIC(15,5)), dates (UTC), UUIDs. \-\> \[Link to: Core_Principle_DataFormats.md\]
   9. **System Architecture Overview:** High-level component diagram and interaction model. \-\> \[Link to: System_Architecture_Overview.md\]

3. **Key Business Modules & Flows** _(For each module: brief purpose, link to DDLs within the Master DDL file, link to BLA, and key high-level flows)_

   1. #### **Foundation & Administration Module**

      1. **Purpose:** System setup, user/company management, core lookups.
      2. **DDL Reference:** See "Foundation Entities" section in HyperM_V2_Schema_Consolidated_vX.Y.Z.sql. (Covers: users, roles, companies, company_memberships, company_locations, etc.)
      3. **BLA:** \-\> \[Link to: BLA_Module_FoundationAdmin.md\]
      4. **High-Level Flows:** New company onboarding; User invitation & role assignment; Managing company settings & locations.

   2. #### **Partners Module (CRM \- Customers & Suppliers)**

      1. **Purpose:** Manage customer and supplier data; provide a central view of partner interactions.
      2. **DDL Reference:** See "Partners Module" section in HyperM_V2_Schema_Consolidated_vX.Y.Z.sql. (Covers: partners, partner_translations, partner_type_enum, vat_responses)
      3. **BLA:** \-\> \[Link to: BLA_Module_Partners.md\]
      4. **High-Level Flows:** Partner creation/editing; Partner selection in sales/purchasing; Viewing partner-specific documents (invoices, orders, subscriptions) and activity summaries.

   3. **Product & Service Catalog Module (Nomenclatures)**
      1. **Purpose:** Define all sellable/purchasable items, services, assets, and subscription plans, including their inventory tracking behavior and default pricing.
      2. **DDL Reference:** See "Nomenclatures & Product Catalog Module" section in HyperM_V2_Schema_Consolidated_vX.Y.Z.sql. (Covers: nomenclature_types, nomenclature_unit, nomenclatures, nomenclature_translations)
      3. **BLA:** \-\> \[Link to: BLA_Module_Nomenclatures.md\]
      4. **High-Level Flows:** Item definition; Item selection in transactional documents; Default price/VAT determination.
   4. **Sales & Ordering Module**
      1. **Purpose:** Capture customer orders (standard B2B, POS) and manage the pre-fulfillment/pre-invoicing stage.
      2. **DDL Reference:** See "Sales & Ordering Module" section in HyperM_V2_Schema_Consolidated_vX.Y.Z.sql. (Covers: sales_order_status_enum, order_item_fulfillment_status_enum, sales_orders, sales_order_items)
      3. **BLA:** \-\> \[Link to: BLA_Module_SalesAndOrdering.md\] **(To be created next)**
      4. **High-Level Flows:** Standard order creation & confirmation; POS transaction processing; Pricing engine application; Stock allocation requests.
   5. **Inventory Management Module**
      1. **Purpose:** Track actual physical stock quantities, costs, specific tracking details (batch/serial), and movements across storage locations.
      2. **DDL Reference:** See "Inventory Management Module" (Storages, Core Stock, Stock Auditing sections) in HyperM_V2_Schema_Consolidated_vX.Y.Z.sql. (Covers: storages, inventory_stock_items, stock_allocations, stock_movements_log, and related ENUMs)
      3. **BLA:** \-\> \[Link to: BLA_Module_Inventory.md\]
      4. **High-Level Flows:** Stock intake from goods receipt; Stock dispatch for sales fulfillment; Internal stock transfers; Stock adjustments; Real-time quantity updates based on movements.
   6. **Procurement & Purchasing Module**
      1. **Purpose:** Manage the process of ordering goods and services from suppliers.
      2. **DDL Reference:** See "Procurement & Purchasing Module" section in HyperM_V2_Schema_Consolidated_vX.Y.Z.sql. (Covers: purchase_order_status_enum, purchase_orders, purchase_order_items)
      3. **BLA:** \-\> \[Link to: BLA_Module_Procurement.md\]
      4. **High-Level Flows:** Purchase order creation; Sending PO to supplier; Linking PO to goods receipt.
   7. **Goods Receipt Module**
      1. **Purpose:** Record the physical receipt of goods into inventory, often against purchase orders.
      2. **DDL Reference:** See "Inventory Management Module" (Goods Receipt section) in HyperM_V2_Schema_Consolidated_vX.Y.Z.sql. (Covers: grn_status_enum, goods_receipt_notes, goods_receipt_note_items)
      3. **BLA:** \-\> \[Link to: BLA_Module_GoodsReceipt.md\]
      4. **High-Level Flows:** Receiving items against a PO or ad-hoc; Recording quantities, costs, batch/serial info; Updating inventory stock levels.
   8. **Invoicing & Financial Documents Module**
      1. **Purpose:** Generate and manage legally compliant financial documents including standard invoices, credit/debit notes, and handle advance payment invoicing and reconciliation.
      2. **DDL Reference:** See "Invoicing & Financial Documents Module" section in HyperM_V2_Schema_Consolidated_vX.Y.Z.sql. (Covers: invoice_status_enum, invoice_vat_summary_enum, payment_methods, payment_terms, vat_rules_and_exemptions, invoices, invoice_items, credit_notes, credit_note_items, debit_notes, debit_note_items)
      3. **BLA:** \-\> \[Link to: BLA_Module_InvoicingFinancialDocs.md\]
      4. **High-Level Flows:** Issuing invoices from sales orders/subscriptions; Issuing advance payment invoices upon fund receipt; Creating final invoices that offset multiple advances; Generating credit/debit notes against existing invoices.
   9. **Subscriptions Module**
      1. **Purpose:** Manage recurring service agreements and automate periodic billing.
      2. **DDL Reference:** See "Subscriptions Module" section in HyperM_V2_Schema_Consolidated_vX.Y.Z.sql. (Covers: subscription_status_enum, subscriptions)
      3. **BLA:** \-\> \[Link to: BLA_Module_Subscriptions.md\]
      4. **High-Level Flows:** Subscription setup & activation; Automated generation of invoices based on billing cycle and next billing date.
   10. **Fiscalization Module**

       1. **Purpose:** Handle interactions with fiscal devices for legally required transaction registration and record fiscal receipts.
       2. **DDL Reference:** See "Fiscalization Module" section in HyperM_V2_Schema_Consolidated_vX.Y.Z.sql. (Covers: fiscal_receipt_status_enum, fiscal_receipts, fiscal_receipt_items)
       3. **BLA:** \-\> \[Link to: BLA_Module_Fiscalization.md\]
       4. **High-Level Flows:** Generating fiscal receipts for POS transactions; Generating fiscal receipts for invoice payments made via fiscalizable methods (e.g., cash, card), including advance payment invoices.

   11. #### **Platform Subscription & Plan Management Module (NEW ENTRY)**

       1. **Purpose:** Manages the SaaS subscription plans offered by Hyper M v2 to its tenant companies, including trial periods, plan selection, feature gating, and billing for platform usage.
       2. **DDL Reference:** See "SaaS Platform Management" section in \`HyperM_V2_Schema_Consolidated_vX.Y.Z.sql\`. (Covers: \`saas_plans\`, \`saas_plan_features\`, \`company_saas_subscriptions\`, etc. \- \*These DDLs will be defined when we work on this BLA\*).
       3. **BLA:** \-\> \[Link to: \`BLA_Module_PlatformSubscriptionPlanManagement.md\`\]
       4. **High-Level Flows:** New company trial initiation; Trial expiry notifications & conversion to paid plan; Plan upgrades/downgrades; Payment processing (Card & Bank Transfer); Feature access control based on plan; Downgrade to free tier on non-payment.

4. ### **Future Module Placeholders _(This section can be populated as new major functional areas are identified for future development)_**

   1. Quotes Module
   2. Delivery Notes / Shipments Module
   3. Advanced Inventory (Physical Items, Batch Details, Stock Takes)
   4. Manufacturing/Production Module
   5. Reporting & Analytics Module  


5. **Glossary of Terms** \* \-\> \[Link to: Glossary.md\] (Common terms and definitions used across the project)
