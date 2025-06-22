# AGENTS.MD - Guiding Jules for the Hyper M v2 Project

This document helps Jules (and human developers) understand the Hyper M v2 project structure, key architectural decisions, and where to find detailed information.

## 1. Overall Project Goal & Architecture

Hyper M v2 is a SaaS platform designed to streamline core business operations for SMEs. Key functionalities include CRM, product catalog, inventory, invoicing, sales/procurement, fiscalization, and user management.

**Core Documentation:**

- **Master Blueprint:** The primary source of truth for business logic, user roles, tech stack, global principles, and database schema overview is the [Hyper M v2: Master Blueprint (Version 1.0.7 - Consolidated)](./docs/HyperM_Master_Blueprint.md). **Jules should frequently refer to this document, especially Sections I (Core Logic), III (Tech Stack), IV (Global Principles), and VI (Architectural Decisions).**
- **Database Schema:** The definitive DDL is in [HyperM_V2_Schema_Consolidated_v1.0.7.sql](./docs/schema/HyperM_V2_Schema_Consolidated_v1.0.7.sql). All database changes must be reflected here and adhere to its structure.
- **Functional & Navigational Map:** For an overview of how modules connect and where to find BLA documents, refer to the "Functional & Navigational Map" (Section IX.C of the Master Blueprint or a separate linked file if you create one).

## 2. Key Technology Choices & Implications

- **Frontend:** Angular (SSR) - See Master Blueprint Section III.
- **Backend API Gateway:** Hasura DDN (v3) - See Master Blueprint Section III.
  - All primary data access should be via Hasura GraphQL.
  - Custom business logic often resides in Hasura Connectors (TypeScript/Node.js).
- **Backend Services (Node.js/Express):** For Auth, Webhooks, File Handling, Fiscal Integration - See Master Blueprint Section III.
- **Database:** PostgreSQL - Schema is in [./docs/schema/HyperM_V2_Schema_Consolidated_v1.0.7.sql](./docs/schema/HyperM_V2_Schema_Consolidated_v1.0.7.sql).

## 3. Business Logic Addendums (BLAs)

Detailed specifications for each module's business logic are documented in Business Logic Addendums (BLAs). These are critical for implementing features correctly.

- **Location:** All BLAs are located in the [./docs/blas/](./docs/blas/) directory.
- **Current BLAs include:**
  - [BLA: User Authentication & Onboarding](./docs/blas/BLA_Module_AuthAndOnboarding.md)
  - [BLA: Company & User Management](./docs/blas/BLA_Module_CompanyUserManagement.md)
  - [BLA: Platform Subscription & Plan Management](./docs/blas/BLA_Module_PlatformSubscriptionPlanManagement.md)
  - _(Add links as more are created)_
- **When working on a specific module, Jules MUST consult the corresponding BLA document.** For example, for tasks related to "Platform Subscription," refer to `BLA_Module_PlatformSubscriptionPlanManagement.md`.
- **BLA Template:** All BLAs follow a standard template defined in Section IX.B of the Master Blueprint.

## 4. Core System Principles for Jules to Uphold:

(Summarize the most critical ones from your Master Blueprint Section IV & VI, with links if necessary)

- **Multi-Tenancy:** Data is strictly scoped by `company_id`. Backend logic must filter by `X-Hasura-Company-ID`. (See Master Blueprint Section IV).
- **Monetary Values:** Store and handle as `NUMERIC(15, 5)`. (See Master Blueprint Section IV).
- **Primary Keys:** Use UUIDs. (See Master Blueprint Section IV).
- **Translations:** Use `_translations` tables with JSONB. (See Master Blueprint Section IV).
- **Immutability of Financial Records:** Finalized financial documents are immutable. (See Master Blueprint Section IV & VI).
- **Document Numbering:** Use the centralized `get_next_document_number()` function. (See Master Blueprint Section IV).

## 5. Specific "Code Agents" or Tools (If Applicable)

_(This is the original intent of AGENTS.MD. If you have internal scripts, CLI tools, linters with custom rules, or CI/CD pipeline scripts that Jules should know how to use or respect, describe them here.)_

**Example:**

- **`scripts/generate_migration.sh <migration_name>`:**
  - **Purpose:** Helper script to create a new Hasura/Postgres migration file with the correct naming convention and timestamp.
  - **Usage:** Run this script before making any schema changes. Jules, if asked to make a schema change, should first indicate the need to run this script.

## 6. How Jules Should Approach Tasks:

- **Understand Scope:** Before coding, ensure the task is well-defined and references the relevant BLA and Master Blueprint sections.
- **Adhere to Schema:** All database interactions must align with [./docs/schema/HyperM_V2_Schema_Consolidated_v1.0.7.sql](./docs/schema/HyperM_V2_Schema_Consolidated_v1.0.7.sql).
- **Follow BLAs:** Feature implementation must follow the logic outlined in the respective BLA from [./docs/blas/](./docs/blas/).
- **Ask Clarifying Questions:** If requirements in a BLA or the Master Blueprint are unclear or seem contradictory for a given task, Jules should ask for clarification.
- **Maintain Consistency:** New code should follow the patterns, styles, and architectural decisions present in the existing codebase and documented principles.
