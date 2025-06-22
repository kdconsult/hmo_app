-- #############################################################################
-- #
-- # Part V: Database Schema (DDL - V2 Finalized/Drafted)
-- # (Content moved to HyperM_V2_Schema_Consolidated_v1.0.0.sql)
-- #
-- #############################################################################

CREATE OR REPLACE FUNCTION public.set_current_timestamp_updatedAt()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- #############################################################################
-- # A. Core Foundation Entities
-- #############################################################################
-- These are foundational tables for users, companies, locations, roles, partners,
-- and basic lookups like locales and countries.

-- ## A.1. Roles and Users

-- ### `public.roles`
CREATE TABLE IF NOT EXISTS public.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    value TEXT UNIQUE NOT NULL,                   -- Programmatic identifier (e.g., 'admin', 'manager', 'sales_rep')
    description TEXT NOT NULL,                    -- User-friendly description/display name
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE OR REPLACE TRIGGER set_public_roles_updated_at
    BEFORE UPDATE ON public.roles
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.roles IS 'Defines user roles within the system (e.g., admin, manager).';
COMMENT ON COLUMN public.roles.value IS 'Programmatic identifier for the role (e.g., ''admin'', ''manager'').';
COMMENT ON COLUMN public.roles.description IS 'User-friendly description or display name for the role.';

-- ### `public.users`
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,                       -- Global unique identifier for login
    password_hash TEXT NOT NULL,                      -- Stores hashed passwords
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    first_name TEXT NOT NULL,                         -- Required for core business documents
    last_name TEXT NOT NULL,                          -- Required for core business documents
    middle_name TEXT,                                 -- Optional
    -- Audit fields
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE               -- For soft deletes
);
CREATE OR REPLACE TRIGGER set_public_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.users IS 'Stores global user accounts for Hyper M v2.';
COMMENT ON COLUMN public.users.email IS 'Primary email address of the user, used for login and global identification.';
COMMENT ON COLUMN public.users.password_hash IS 'Securely hashed password for authentication.';
COMMENT ON COLUMN public.users.email_verified IS 'Flag indicating if the user''s email address has been verified.';
COMMENT ON COLUMN public.users.first_name IS 'User''s first name.';
COMMENT ON COLUMN public.users.last_name IS 'User''s last name.';
COMMENT ON COLUMN public.users.deleted_at IS 'Timestamp for soft deletion of user accounts.';


-- ## A.2. Company Structure

-- ### `public.company_membership_status_enum`
CREATE TYPE public.company_membership_status_enum AS ENUM (
    'pending',  -- Invitation sent, awaiting acceptance
    'active',   -- User is an active member
    'inactive', -- User's membership is temporarily suspended
    'removed'   -- User has been permanently removed for historical/auditing
);
COMMENT ON TYPE public.company_membership_status_enum IS 'Defines the possible statuses of a user''s membership within a company.';

-- ### `public.company_memberships`
CREATE TABLE IF NOT EXISTS public.company_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,            -- Foreign key to the global users table
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,     -- Foreign key to the companies table
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,            -- Foreign key to the roles table, defining the user's role within THIS company
    status public.company_membership_status_enum NOT NULL DEFAULT 'pending', -- Current status of the membership (ENUM type)
    invited_by_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,          -- User who sent the invitation (NULL if user created own company)
    invited_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),   -- Timestamp of invitation
    accepted_at TIMESTAMP WITH TIME ZONE,                         -- Timestamp when status transitioned to 'active' (managed by app logic)
    deleted_at TIMESTAMP WITH TIME ZONE,                          -- Timestamp of soft deletion/removal (managed by app logic)
    notes TEXT,                                                   -- Optional notes/reason for status changes (e.g., removal, inactivation)
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT company_memberships_unique_user_company UNIQUE (user_id, company_id, deleted_at) -- Ensures a user can only have one active/pending/inactive membership record per company. `deleted_at` added to allow re-inviting a 'removed' user.
    -- If re-inviting a 'removed' user should create a new record vs reactivating, then UNIQUE (user_id, company_id) is fine if 'removed' means truly soft-deleted and a new invite makes a new row.
    -- Current BLA implies 'removed' is a final state for that membership record, so UNIQUE (user_id, company_id) should be sufficient. Let's stick to:
    -- CONSTRAINT company_memberships_unique_user_company UNIQUE (user_id, company_id) -- Ensures a user can only have one membership record per company
);
-- Re-evaluating the unique constraint based on BLA logic: A user is either pending, active, inactive, or removed. 'removed' is a final state for *that membership instance*.
-- If a user is 'removed' and then re-invited, it should ideally be a *new* membership instance.
-- However, to allow querying history easily, perhaps `UNIQUE (user_id, company_id)` is too strict if we want to allow multiple 'removed' entries over time for audit if they are hard-deleted and re-added.
-- Given `deleted_at` is on the membership, if `deleted_at` is NULL for active/pending/inactive, then `UNIQUE (user_id, company_id)` where `deleted_at IS NULL` is better.
-- For now, let's use the one from the original blueprint which was just `UNIQUE (user_id, company_id)`. This means a user cannot be re-invited if a `removed` record exists unless that record is truly deleted or the `status` field is changed.
-- The BLAs suggest `removed` sets `deleted_at`, so the `company_memberships_unique_user_company` is fine as is.
ALTER TABLE public.company_memberships DROP CONSTRAINT IF EXISTS company_memberships_unique_user_company;
ALTER TABLE public.company_memberships ADD CONSTRAINT company_memberships_unique_user_company UNIQUE (user_id, company_id);


CREATE OR REPLACE TRIGGER set_public_company_memberships_updated_at
    BEFORE UPDATE ON public.company_memberships
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.company_memberships IS 'Links users to companies, defining their role and status within each company.';
COMMENT ON COLUMN public.company_memberships.status IS 'Current status of the user''s membership in the company (e.g., pending, active, inactive, removed).';
COMMENT ON COLUMN public.company_memberships.invited_by_user_id IS 'The user who initiated the invitation for this membership.';
COMMENT ON COLUMN public.company_memberships.accepted_at IS 'Timestamp when the user accepted the invitation and the membership became active.';
COMMENT ON COLUMN public.company_memberships.deleted_at IS 'Timestamp for soft deletion of the membership (when status becomes ''removed'').';


-- ### `public.company_types`
CREATE TABLE IF NOT EXISTS public.company_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type_key TEXT UNIQUE NOT NULL, -- e.g., 'LTD', 'SOLE_PROPRIETOR', 'NGO'
    name TEXT NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE OR REPLACE TRIGGER set_public_company_types_updated_at
    BEFORE UPDATE ON public.company_types
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.company_types IS 'Lookup table for different types of legal company structures (e.g., LTD, Sole Proprietor).';
COMMENT ON COLUMN public.company_types.type_key IS 'Unique programmatic key for the company type.';

-- ### `public.companies`
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    legal_responsible_person TEXT,
    phone TEXT NOT NULL,
    email TEXT,
    vat TEXT UNIQUE, -- VAT numbers are globally unique for active companies
    eik TEXT NOT NULL UNIQUE, -- EIK numbers are globally unique for active companies
    company_type_id UUID NOT NULL REFERENCES public.company_types(id) ON DELETE RESTRICT,
    uses_supto BOOLEAN NOT NULL DEFAULT FALSE,
    country_id UUID NOT NULL REFERENCES public.countries(id) ON DELETE RESTRICT,
    default_locale_id UUID NOT NULL REFERENCES public.locales(id) ON DELETE RESTRICT,
    default_currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT,
    settings JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_vat_registered BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE
);
CREATE OR REPLACE TRIGGER set_public_companies_updated_at
    BEFORE UPDATE ON public.companies
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

-- Adding partial unique indexes for VAT and EIK to only consider non-deleted companies
CREATE UNIQUE INDEX IF NOT EXISTS companies_vat_unique_active ON public.companies (vat) WHERE deleted_at IS NULL AND vat IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS companies_eik_unique_active ON public.companies (eik) WHERE deleted_at IS NULL AND eik IS NOT NULL;
-- Drop the original stricter unique constraints if they exist from initial DDL to avoid conflict
ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_vat_key;
ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_eik_key;


COMMENT ON TABLE public.companies IS 'Represents tenant companies using the Hyper M v2 platform.';
COMMENT ON COLUMN public.companies.name IS 'Official name of the company.';
COMMENT ON COLUMN public.companies.legal_responsible_person IS 'Name of the person legally responsible for the company (e.g., MOL).';
COMMENT ON COLUMN public.companies.vat IS 'Company''s VAT registration number. Must be unique among active companies if provided.';
COMMENT ON COLUMN public.companies.eik IS 'Company''s unique identification code (e.g., EIK in Bulgaria). Must be unique among active companies.';
COMMENT ON COLUMN public.companies.company_type_id IS 'FK to company_types defining the legal structure.';
COMMENT ON COLUMN public.companies.uses_supto IS 'Indicates if the company uses SUPTO (System for Managing Sales in Retail Outlets - BG specific).';
COMMENT ON COLUMN public.companies.country_id IS 'Primary country of operation/registration for the company.';
COMMENT ON COLUMN public.companies.default_locale_id IS 'Default language and regional settings for the company.';
COMMENT ON COLUMN public.companies.default_currency_id IS 'Default financial reporting currency for the company.';
COMMENT ON COLUMN public.companies.settings IS 'JSONB field for storing various company-specific settings and configurations (excluding SaaS plan details).';
COMMENT ON COLUMN public.companies.is_vat_registered IS 'Indicates if the company is currently VAT registered.';
COMMENT ON COLUMN public.companies.deleted_at IS 'Timestamp for soft deletion of company records.';


-- ### `public.company_translations`
CREATE TABLE IF NOT EXISTS public.company_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    locale_id UUID NOT NULL REFERENCES public.locales(id) ON DELETE RESTRICT,
    translation JSONB NOT NULL, -- e.g., {"name": "...", "legal_responsible_person": "..."}
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT company_translations_company_locale_unique UNIQUE (company_id, locale_id)
);
CREATE OR REPLACE TRIGGER set_public_company_translations_updated_at
    BEFORE UPDATE ON public.company_translations
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.company_translations IS 'Stores translations for user-facing text fields of the companies table.';
COMMENT ON COLUMN public.company_translations.translation IS 'JSONB object containing key-value pairs of translated fields from the parent companies table (e.g., "name", "legal_responsible_person").';

-- ### `public.company_locations`
CREATE TABLE IF NOT EXISTS public.company_locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    address_line1 TEXT NOT NULL,
    address_line2 TEXT,
    city TEXT NOT NULL,
    region_name TEXT,
    post_code TEXT,
    country_id UUID NOT NULL REFERENCES public.countries(id) ON DELETE RESTRICT,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT company_locations_company_name_unique UNIQUE (company_id, name, deleted_at) -- Name should be unique per company for active locations.
    -- Re-evaluating: a company can have multiple locations with the same name if one is deleted.
    -- So, unique for non-deleted ones:
);
ALTER TABLE public.company_locations DROP CONSTRAINT IF EXISTS company_locations_company_name_unique;
CREATE UNIQUE INDEX IF NOT EXISTS company_locations_company_name_unique_active ON public.company_locations (company_id, name) WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS company_locations_single_default_per_company
    ON public.company_locations (company_id)
    WHERE is_default = TRUE AND deleted_at IS NULL; -- Only one active default location per company

CREATE OR REPLACE TRIGGER set_public_company_locations_updated_at
    BEFORE UPDATE ON public.company_locations
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.company_locations IS 'Defines operational locations or branches for a company.';
COMMENT ON COLUMN public.company_locations.name IS 'Name of the company location (e.g., "Main Office", "Warehouse West"). Unique per company for active locations.';
COMMENT ON COLUMN public.company_locations.is_default IS 'Indicates if this is the primary/default operational location for the company. Only one active location can be default.';
COMMENT ON COLUMN public.company_locations.deleted_at IS 'Timestamp for soft deletion of company locations.';


-- ### `public.company_location_translations`
CREATE TABLE IF NOT EXISTS public.company_location_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_location_id UUID NOT NULL REFERENCES public.company_locations(id) ON DELETE CASCADE,
    locale_id UUID NOT NULL REFERENCES public.locales(id) ON DELETE RESTRICT,
    translation JSONB NOT NULL, -- e.g. {"name": "...", "address_line1": "..."}
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT company_location_translations_location_locale_unique UNIQUE (company_location_id, locale_id)
);
CREATE OR REPLACE TRIGGER set_public_company_location_translations_updated_at
    BEFORE UPDATE ON public.company_location_translations
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.company_location_translations IS 'Stores translations for user-facing text fields of the company_locations table.';
COMMENT ON COLUMN public.company_location_translations.translation IS 'JSONB object containing key-value pairs of translated fields from company_locations (e.g., "name", "address_line1").';


-- ### `public.company_user_operator_status_enum`
CREATE TYPE public.company_user_operator_status_enum AS ENUM (
    'active',   -- The operator ID is currently assigned and in use
    'inactive', -- Temporarily not in use (e.g., user on leave, printer offline)
    'removed'   -- Permanently unassigned (record preserved for history/audit)
);
COMMENT ON TYPE public.company_user_operator_status_enum IS 'Defines the status of a user''s assignment as an operator (e.g., for a fiscal device) at a company location.';

-- ### `public.company_user_operators`
CREATE TABLE IF NOT EXISTS public.company_user_operators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,                  -- Foreign key to the global user
    company_location_id UUID NOT NULL REFERENCES public.company_locations(id) ON DELETE CASCADE, -- Foreign key to the specific company location
    operator_id TEXT NOT NULL,                                          -- The unique ID for the fiscal printer operator at this location
    status public.company_user_operator_status_enum NOT NULL DEFAULT 'active', -- Status of this operator assignment (ENUM type)
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE                                 -- Timestamp when status transitioned to 'removed' (managed by app logic)
);
-- Partial Unique Index 1: Ensures an operator_id is unique per location for active assignments
CREATE UNIQUE INDEX IF NOT EXISTS company_user_operators_unique_active_per_location
    ON public.company_user_operators (company_location_id, operator_id)
    WHERE status = 'active';
-- Partial Unique Index 2: Ensures a user has only one active operator_id per location
CREATE UNIQUE INDEX IF NOT EXISTS company_user_operators_unique_active_user_location
    ON public.company_user_operators (user_id, company_location_id)
    WHERE status = 'active';

CREATE OR REPLACE TRIGGER set_public_company_user_operators_updated_at
    BEFORE UPDATE ON public.company_user_operators
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.company_user_operators IS 'Links a user to a specific fiscal operator ID within a company location, primarily for fiscal receipt systems and other location-specific user identifiers.';
COMMENT ON COLUMN public.company_user_operators.operator_id IS 'The unique identifier for a user as an operator on a fiscal device, specific to a company location. Can be extended for other similar identifiers (e.g., terminal license).';
COMMENT ON COLUMN public.company_user_operators.status IS 'Current status of this operator ID assignment (active, inactive, removed).';
COMMENT ON COLUMN public.company_user_operators.deleted_at IS 'Timestamp for soft deletion if ''removed'' status implies a soft delete.';


-- ## A.3. Global Lookups

-- ### `public.locales`
CREATE TABLE IF NOT EXISTS public.locales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,                   -- e.g., 'en-US', 'bg-BG', 'es-ES' (for language + region)
    name TEXT NOT NULL,                          -- e.g., 'English (United States)', 'Български (България)'
    is_active BOOLEAN NOT NULL DEFAULT TRUE,     -- Can deactivate locales
    settings JSONB NOT NULL DEFAULT '{}'::jsonb, -- For locale-specific configurations (e.g., {'direction': 'ltr', 'date_format': 'DD/MM/YYYY'})
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE OR REPLACE TRIGGER set_public_locales_updated_at
    BEFORE UPDATE ON public.locales
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.locales IS 'Defines supported locales (language and regional settings) in the system.';
COMMENT ON COLUMN public.locales.code IS 'Standard locale code (e.g., en-US, bg-BG).';
COMMENT ON COLUMN public.locales.name IS 'User-friendly name of the locale.';
COMMENT ON COLUMN public.locales.settings IS 'JSONB for locale-specific settings like date format, text direction.';

-- ### `public.countries`
CREATE TABLE IF NOT EXISTS public.countries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,                          -- e.g., 'BG', 'US' (Country Code - distinct from locale codes)
    name TEXT NOT NULL,                                 -- Primary/default language country name (e.g., 'Bulgaria', 'United States')
    region TEXT NOT NULL,                               -- Primary/default language region name (e.g., 'Europe', 'European Union')
    for_companies BOOLEAN NOT NULL DEFAULT FALSE,       -- If the country can be selected for companies
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE OR REPLACE TRIGGER set_public_countries_updated_at
    BEFORE UPDATE ON public.countries
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.countries IS 'Defines countries used in the system, primarily for addressing and company registration.';
COMMENT ON COLUMN public.countries.code IS 'Standard ISO 3166-1 alpha-2 country code.';
COMMENT ON COLUMN public.countries.name IS 'Primary (often English) name of the country.';
COMMENT ON COLUMN public.countries.region IS 'Geographical or economic region the country belongs to.';
COMMENT ON COLUMN public.countries.for_companies IS 'Indicates if this country can be selected as a company''s country of registration.';

-- ### `public.country_translations`
CREATE TABLE IF NOT EXISTS public.country_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    locale_id UUID NOT NULL REFERENCES public.locales(id) ON DELETE RESTRICT,
    country_id UUID NOT NULL REFERENCES public.countries(id) ON DELETE CASCADE,
    translation JSONB NOT NULL,                          -- Contains translated: name, region (e.g., {'name': 'Франция', 'region': 'Европейска Общност'})
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT country_translations_locale_country_id_key UNIQUE (locale_id, country_id)
);
CREATE OR REPLACE TRIGGER set_public_country_translations_updated_at
    BEFORE UPDATE ON public.country_translations
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.country_translations IS 'Stores translations for country names and regions into different locales.';
COMMENT ON COLUMN public.country_translations.translation IS 'JSONB object containing translated "name" and "region" for the country.';

-- ## A.4. Partners (Basic Structure - Detailed in Partners Module)

-- ### `public.partner_type_enum`
CREATE TYPE public.partner_type_enum AS ENUM (
    'individual',         -- Represents an individual person (e.g., a customer)
    'legal_entity'        -- Represents an external business or organization
);
COMMENT ON TYPE public.partner_type_enum IS 'Defines the type of a partner: an individual or a legal entity.';

-- ### `public.partners`
CREATE TABLE IF NOT EXISTS public.partners (
    id UUID PRIMARY KEY DEFAULT public.gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE RESTRICT, -- The Hyper M v2 company that manages this partner record
    -- Core Partner Identity & Contact Information
    name TEXT NOT NULL,                                   -- Name of the partner (company name or individual's full name).
    legal_responsible_person TEXT,                        -- The legally accountable person for the partner (e.g., MOL). Only for 'legal_entity' type.
    phone TEXT,
    email TEXT,
    country_id UUID REFERENCES public.countries (id) ON DELETE RESTRICT,     -- Partner's country of registration/residence
    -- Identifiers (Nullable based on partner_type)
    eik TEXT,                                             -- Legal identification code (e.g., EIK). Only for 'legal_entity' type.
    vat TEXT,                                             -- VAT registration number. Only for 'legal_entity' type, if VAT registered.
    -- Address Details
    address_line1 TEXT,
    address_line2 TEXT,
    city TEXT,
    region_name TEXT,
    post_code TEXT,
    -- Partner Type
    partner_type public.partner_type_enum NOT NULL,       -- Defines the type of partner (individual, legal_entity)
    -- Audit fields
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE
);
-- Unique Indexes for 'legal_entity' partners (scoped per 'company_id' for active partners)
CREATE UNIQUE INDEX IF NOT EXISTS partners_unique_legal_entity_eik_per_company_active
    ON public.partners (company_id, eik)
    WHERE partner_type = 'legal_entity' AND eik IS NOT NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS partners_unique_legal_entity_vat_per_company_active
    ON public.partners (company_id, vat)
    WHERE partner_type = 'legal_entity' AND vat IS NOT NULL AND deleted_at IS NULL;

-- CHECK Constraints for data consistency based on partner_type
ALTER TABLE public.partners ADD CONSTRAINT check_partner_type_data_consistency
    CHECK (
        (partner_type = 'individual' AND eik IS NULL AND vat IS NULL AND name IS NOT NULL) OR
        (partner_type = 'legal_entity' AND eik IS NOT NULL AND name IS NOT NULL)
    );
-- Audit Trigger
CREATE OR REPLACE TRIGGER set_public_partners_updated_at
    BEFORE UPDATE ON public.partners
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.partners IS 'Represents external business partners (customers, suppliers) for a tenant company.';
COMMENT ON COLUMN public.partners.name IS 'Primary name of the partner (company name or individual''s full name).';
COMMENT ON COLUMN public.partners.legal_responsible_person IS 'Legally accountable person for ''legal_entity'' type partners (e.g., MOL).';
COMMENT ON COLUMN public.partners.eik IS 'Legal identification code (e.g., EIK) for ''legal_entity'' type partners.';
COMMENT ON COLUMN public.partners.vat IS 'VAT registration number for ''legal_entity'' type partners, if applicable.';
COMMENT ON COLUMN public.partners.partner_type IS 'Distinguishes between individual and legal entity partners.';
COMMENT ON COLUMN public.partners.deleted_at IS 'Timestamp for soft deletion of partner records.';


-- ### `public.partner_translations`
CREATE TABLE IF NOT EXISTS public.partner_translations (
    id UUID PRIMARY KEY DEFAULT public.gen_random_uuid(),
    locale_id UUID NOT NULL REFERENCES public.locales(id) ON DELETE RESTRICT,
    partner_id UUID NOT NULL REFERENCES public.partners (id) ON DELETE CASCADE,
    translation JSONB NOT NULL,                           -- Contains translated: name, legal_responsible_person, address_line1, address_line2, city, region_name
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT partner_translations_locale_partner_id_key UNIQUE (locale_id, partner_id)
);
CREATE OR REPLACE TRIGGER set_public_partner_translations_updated_at
    BEFORE UPDATE ON public.partner_translations
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.partner_translations IS 'Stores translations for user-facing text fields of the partners table.';
COMMENT ON COLUMN public.partner_translations.translation IS 'JSONB object translating partner fields: name, legal_responsible_person, and address components.';


-- ## A.5. Currency & Financial Setup

-- ### `public.currencies`
CREATE TABLE IF NOT EXISTS public.currencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL, -- ISO 4217 currency code, e.g., 'USD', 'EUR', 'BGN'
    name TEXT NOT NULL,        -- e.g., "US Dollar", "Euro", "Bulgarian Lev"
    symbol TEXT NOT NULL,      -- e.g., "$", "€", "лв."
    decimal_places INTEGER NOT NULL DEFAULT 2 CHECK (decimal_places >= 0 AND decimal_places <= 5), -- Number of decimal places commonly used
    is_system_default BOOLEAN NOT NULL DEFAULT FALSE, -- Indicates if this is the ultimate fallback/system base currency (only one true)
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS currencies_is_system_default_true_unique
    ON public.currencies (is_system_default)
    WHERE is_system_default = TRUE;
CREATE OR REPLACE TRIGGER set_public_currencies_updated_at
    BEFORE UPDATE ON public.currencies
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.currencies IS 'Defines currencies used in the system, their codes, symbols, and decimal precision.';
COMMENT ON COLUMN public.currencies.code IS 'Standard ISO 4217 currency code.';
COMMENT ON COLUMN public.currencies.decimal_places IS 'Number of decimal places typically used for this currency in transactions and display.';
COMMENT ON COLUMN public.currencies.is_system_default IS 'Flag to identify a single system-wide default/base currency, if needed beyond company defaults.';


-- ### `public.company_currency_settings`
CREATE TABLE IF NOT EXISTS public.company_currency_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT,
    is_default_for_company BOOLEAN NOT NULL DEFAULT FALSE, -- True if this is the company's primary accounting/reporting currency
    effective_from_date DATE NOT NULL,
    effective_to_date DATE NULLABLE, -- NULL means currently effective
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT company_currency_settings_company_currency_effective_range
        UNIQUE (company_id, currency_id, effective_from_date) -- A currency can only have one setting starting on a specific date
);
CREATE INDEX IF NOT EXISTS idx_ccs_company_id_currency_id ON public.company_currency_settings(company_id, currency_id);
CREATE UNIQUE INDEX IF NOT EXISTS company_currency_settings_one_current_default
    ON public.company_currency_settings (company_id)
    WHERE is_default_for_company = TRUE AND effective_to_date IS NULL;
CREATE OR REPLACE TRIGGER set_public_company_currency_settings_updated_at
    BEFORE UPDATE ON public.company_currency_settings
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.company_currency_settings IS 'Manages currencies used by a company, its default currency, and effective date ranges for these settings (e.g., for Euro adoption).';
COMMENT ON COLUMN public.company_currency_settings.is_default_for_company IS 'Indicates if this is the primary financial reporting currency for the company during the effective period.';
COMMENT ON COLUMN public.company_currency_settings.effective_from_date IS 'Date from which this currency setting is effective for the company.';
COMMENT ON COLUMN public.company_currency_settings.effective_to_date IS 'Date until which this currency setting was effective (NULL if currently active).';


-- ### `public.currency_rates`
CREATE TABLE IF NOT EXISTS public.currency_rates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NULLABLE REFERENCES public.companies(id) ON DELETE RESTRICT, -- Rates can be company-specific or global (NULL company_id)
    rate_date DATE NOT NULL,
    from_currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT, -- The currency being converted FROM
    to_currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT,   -- The currency being converted TO (often the company's default for that rate_date)
    rate_value NUMERIC(19, 9) NOT NULL CHECK (rate_value > 0), -- Exchange rate value (e.g., 1 EUR = X TARGET_CURRENCY)
    source TEXT NULLABLE, -- e.g., "BNB", "ECB", "API:XYZ", "MANUAL"
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT currency_rates_company_date_from_to_unique UNIQUE (company_id, rate_date, from_currency_id, to_currency_id),
    CONSTRAINT currency_rates_global_date_from_to_unique UNIQUE (rate_date, from_currency_id, to_currency_id) WHERE company_id IS NULL
);
CREATE INDEX IF NOT EXISTS idx_cr_company_id_rate_date ON public.currency_rates(company_id, rate_date);
CREATE INDEX IF NOT EXISTS idx_cr_global_rate_date ON public.currency_rates(rate_date) WHERE company_id IS NULL;
CREATE OR REPLACE TRIGGER set_public_currency_rates_updated_at
    BEFORE UPDATE ON public.currency_rates
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.currency_rates IS 'Stores daily exchange rates between currency pairs, potentially scoped by company or global.';
COMMENT ON COLUMN public.currency_rates.company_id IS 'Company for which this rate is applicable. NULL means global/system rate.';
COMMENT ON COLUMN public.currency_rates.rate_date IS 'The date for which this exchange rate is valid.';
COMMENT ON COLUMN public.currency_rates.from_currency_id IS 'The currency being converted from.';
COMMENT ON COLUMN public.currency_rates.to_currency_id IS 'The currency being converted to (often the company''s default currency on rate_date).';
COMMENT ON COLUMN public.currency_rates.rate_value IS 'The multiplier to convert 1 unit of FROM_CURRENCY to TO_CURRENCY.';
COMMENT ON COLUMN public.currency_rates.source IS 'Indicates the source of the exchange rate (e.g., central bank, API).';


-- ## A.6. VAT Related (Basic - Detailed in Invoicing Module)

-- ### `public.fiscal_vat_groups` (If needed for fiscal printer integration)
CREATE TABLE IF NOT EXISTS public.fiscal_vat_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NULLABLE REFERENCES public.companies(id) ON DELETE CASCADE, -- Can be global or company-specific
    group_code TEXT NOT NULL, -- e.g., 'A', 'B', 'C', 'D' (or '1', '2', '3', '4') as per fiscal device spec
    default_vat_rate_percentage NUMERIC(5,2) NOT NULL, -- The VAT rate this group typically represents (e.g., 20.00 for 'A')
    description TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT fiscal_vat_groups_company_code_unique UNIQUE (company_id, group_code),
    CONSTRAINT fiscal_vat_groups_global_code_unique UNIQUE (group_code) WHERE company_id IS NULL
);
CREATE OR REPLACE TRIGGER set_public_fiscal_vat_groups_updated_at
    BEFORE UPDATE ON public.fiscal_vat_groups
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();
COMMENT ON TABLE public.fiscal_vat_groups IS 'Defines VAT groups required by fiscal printers/devices (e.g., "A" for 20%, "B" for 9% in BG). Links to the default rate it represents. Can be global or company-specific.';
COMMENT ON COLUMN public.fiscal_vat_groups.group_code IS 'The specific code (e.g., ''A'', ''1'') used by fiscal devices for this VAT group.';
COMMENT ON COLUMN public.fiscal_vat_groups.default_vat_rate_percentage IS 'The VAT rate this fiscal group typically corresponds to.';


-- ### `public.vat_responses` (For VIES checks)
CREATE TABLE IF NOT EXISTS public.vat_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    partner_id UUID NULLABLE REFERENCES public.partners(id) ON DELETE SET NULL, -- The partner whose VAT ID was checked
    vat_number_queried TEXT NOT NULL,
    queried_member_state_code TEXT NOT NULL, -- Country code of the VAT number
    request_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    is_valid BOOLEAN NOT NULL,
    vies_name TEXT NULLABLE, -- Name returned by VIES
    vies_address TEXT NULLABLE, -- Address returned by VIES
    vies_request_identifier TEXT NULLABLE, -- Unique ID from VIES if provided
    raw_response JSONB NULLABLE, -- Full raw response from VIES API
    error_message TEXT NULLABLE, -- If VIES check failed or returned an error
    checked_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_vr_company_partner_vat ON public.vat_responses(company_id, partner_id, vat_number_queried, request_date);
CREATE OR REPLACE TRIGGER set_public_vat_responses_updated_at
    BEFORE UPDATE ON public.vat_responses
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.vat_responses IS 'Logs responses from VIES (VAT Information Exchange System) checks for partner VAT numbers.';
COMMENT ON COLUMN public.vat_responses.partner_id IS 'Reference to the internal partner record, if the VAT check was for an existing partner.';
COMMENT ON COLUMN public.vat_responses.vat_number_queried IS 'The full VAT number that was submitted to VIES for validation.';
COMMENT ON COLUMN public.vat_responses.queried_member_state_code IS 'The EU member state code part of the VAT number queried.';
COMMENT ON COLUMN public.vat_responses.is_valid IS 'True if VIES confirmed the VAT number as valid on the request_date.';
COMMENT ON COLUMN public.vat_responses.raw_response IS 'Stores the complete raw JSON response received from the VIES service for auditing or debugging.';

-- #############################################################################
-- # B. Nomenclatures & Product Catalog Module
-- #############################################################################
-- DDLs for defining products, services, units, types, and translations.
-- Includes inventory tracking behavior and default pricing.

-- ## B.1. ENUM Types for Nomenclatures

-- ### `public.inventory_tracking_type_enum`
-- This ENUM defines how inventory levels are tracked for a nomenclature.
-- It was likely defined earlier if referenced by other tables, but included here for module completeness.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inventory_tracking_type_enum') THEN
        CREATE TYPE public.inventory_tracking_type_enum AS ENUM (
            'none',             -- Not tracked in inventory (e.g., services, non-stock items)
            'quantity_only',    -- Tracked by total quantity in a storage location
            'batch_tracked',    -- Tracked by quantity per batch, may include expiry dates
            'serial_tracked'    -- Each individual item is tracked by a unique serial number
        );
        COMMENT ON TYPE public.inventory_tracking_type_enum IS 'Defines how inventory is tracked for a nomenclature: none, quantity_only, batch_tracked, or serial_tracked.';
    END IF;
END$$;


-- ## B.2. Core Tables for Nomenclatures

-- ### `public.nomenclature_types`
-- Defines categories for nomenclatures (e.g., Product, Service, Asset, Subscription Plan).
-- These types can be global (company_id IS NULL) or company-specific.
CREATE TABLE IF NOT EXISTS public.nomenclature_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NULLABLE REFERENCES public.companies(id) ON DELETE CASCADE, -- Can be global (NULL) or company-specific
    type_key TEXT NOT NULL,                 -- Programmatic key, e.g., 'PRODUCT_PHYSICAL', 'SERVICE_STD', 'ASSET_INTERNAL', 'SUBSCRIPTION_PLAN_SAAS' (for HyperM's own plans)
    name TEXT NOT NULL,                     -- User-friendly name, e.g., "Physical Product", "Standard Service"
    description TEXT NULLABLE,
    is_stockable BOOLEAN NOT NULL DEFAULT FALSE, -- True if items of this type are typically managed in inventory
    is_sellable BOOLEAN NOT NULL DEFAULT TRUE,
    is_purchasable BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT nomenclature_types_company_key_unique UNIQUE (company_id, type_key),
    CONSTRAINT nomenclature_types_global_key_unique UNIQUE (type_key) WHERE company_id IS NULL
);
CREATE OR REPLACE TRIGGER set_public_nomenclature_types_updated_at
    BEFORE UPDATE ON public.nomenclature_types
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.nomenclature_types IS 'Defines categories for nomenclatures (e.g., product, service, asset, subscription plan). Can be global or company-specific.';
COMMENT ON COLUMN public.nomenclature_types.company_id IS 'If NULL, this type is global. If set, it''s specific to a company.';
COMMENT ON COLUMN public.nomenclature_types.type_key IS 'Unique programmatic key for the nomenclature type (e.g., ''PRODUCT_PHYSICAL'', ''SERVICE'').';
COMMENT ON COLUMN public.nomenclature_types.is_stockable IS 'Indicates if nomenclatures of this type are typically managed in physical inventory.';
COMMENT ON COLUMN public.nomenclature_types.is_sellable IS 'Indicates if nomenclatures of this type can generally be sold.';
COMMENT ON COLUMN public.nomenclature_types.is_purchasable IS 'Indicates if nomenclatures of this type can generally be purchased.';


-- ### `public.nomenclature_unit`
-- Defines units of measure for nomenclatures (e.g., pieces, kg, hours, months).
-- These units can be global (company_id IS NULL) or company-specific.
CREATE TABLE IF NOT EXISTS public.nomenclature_unit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NULLABLE REFERENCES public.companies(id) ON DELETE CASCADE, -- Can be global (NULL) or company-specific
    unit_code TEXT NOT NULL,                -- Short code, e.g., 'PCS', 'KG', 'LTR', 'HR', 'MTH' (month for subscriptions)
    name TEXT NOT NULL,                     -- User-friendly name, e.g., "Pieces", "Kilograms", "Hours", "Month"
    description TEXT NULLABLE,
    decimal_places_allowed INTEGER NOT NULL DEFAULT 0 CHECK (decimal_places_allowed >= 0 AND decimal_places_allowed <= 5), -- For quantity precision
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT nomenclature_unit_company_code_unique UNIQUE (company_id, unit_code),
    CONSTRAINT nomenclature_unit_global_code_unique UNIQUE (unit_code) WHERE company_id IS NULL
);
CREATE OR REPLACE TRIGGER set_public_nomenclature_unit_updated_at
    BEFORE UPDATE ON public.nomenclature_unit
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.nomenclature_unit IS 'Defines units of measure for nomenclatures (e.g., pieces, kg, hours, months). Can be global or company-specific.';
COMMENT ON COLUMN public.nomenclature_unit.company_id IS 'If NULL, this unit is global. If set, it''s specific to a company.';
COMMENT ON COLUMN public.nomenclature_unit.unit_code IS 'Short, unique programmatic code for the unit of measure (e.g., ''PCS'', ''KG'').';
COMMENT ON COLUMN public.nomenclature_unit.decimal_places_allowed IS 'Number of decimal places allowed for quantities using this unit (e.g., 3 for KG, 0 for PCS).';


-- ### `public.nomenclatures`
-- Master catalog for all products, services, assets, and other definable items a company deals with.
CREATE TABLE IF NOT EXISTS public.nomenclatures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT, -- Each nomenclature is specific to a company
    -- Basic Identification
    item_code TEXT NULLABLE,                -- Internal unique code/SKU for this item within the company
    name TEXT NOT NULL,                     -- Primary name of the product/service
    description TEXT NULLABLE,              -- Detailed description
    barcode TEXT NULLABLE,                  -- EAN/UPC or other barcode

    -- Classification & Type
    nomenclature_type_id UUID NOT NULL REFERENCES public.nomenclature_types(id) ON DELETE RESTRICT,
    -- category_id UUID NULLABLE, -- FK to a potential future 'nomenclature_categories' table
    -- brand_id UUID NULLABLE,    -- FK to a potential future 'brands' table

    -- Unit of Measure
    base_unit_id UUID NOT NULL REFERENCES public.nomenclature_unit(id) ON DELETE RESTRICT, -- Primary unit for stock/sale/purchase

    -- Inventory Tracking (Crucial for physical products)
    inventory_tracking_type public.inventory_tracking_type_enum NOT NULL DEFAULT 'none',

    -- Physical Attributes (Optional, more relevant for physical products)
    weight_value NUMERIC(10,3) NULLABLE,
    weight_unit_id UUID NULLABLE REFERENCES public.nomenclature_unit(id) ON DELETE RESTRICT, -- e.g., KG, LB
    volume_value NUMERIC(10,3) NULLABLE,
    volume_unit_id UUID NULLABLE REFERENCES public.nomenclature_unit(id) ON DELETE RESTRICT, -- e.g., M3, LTR
    dimensions_text TEXT NULLABLE,          -- e.g., "10x20x5 cm"

    -- Default Pricing & Costing (Fallbacks or for simple scenarios)
    default_selling_price_inclusive_vat NUMERIC(15,5) NULLABLE,
    default_selling_price_exclusive_vat NUMERIC(15,5) NULLABLE,
    default_selling_price_currency_id UUID NULLABLE REFERENCES public.currencies(id) ON DELETE RESTRICT,
    default_selling_price_vat_rule_id UUID NULLABLE REFERENCES public.vat_rules_and_exemptions(id) ON DELETE RESTRICT, -- Defined in Invoicing Module DDLs

    estimated_default_cost_price NUMERIC(15,5) NULLABLE, -- Standard or estimated cost, actual costs are on inventory_stock_items

    -- Default VAT & Tax Classification
    default_vat_rule_id UUID NULLABLE REFERENCES public.vat_rules_and_exemptions(id) ON DELETE RESTRICT, -- Default VAT rule for sales/purchases. Defined in Invoicing Module DDLs
    -- commodity_code_id UUID NULLABLE, -- FK to customs commodity codes (TARIC/HS) for international trade

    -- Supplier Information (Optional default supplier for this item)
    default_supplier_partner_id UUID NULLABLE REFERENCES public.partners(id) ON DELETE SET NULL,
    default_supplier_item_code TEXT NULLABLE, -- Supplier's code for this item

    -- Flags
    is_active BOOLEAN NOT NULL DEFAULT TRUE,        -- Can this item be used in new transactions?
    is_sellable BOOLEAN NOT NULL DEFAULT TRUE,      -- Can this item be sold? (Overrides type default)
    is_purchasable BOOLEAN NOT NULL DEFAULT TRUE,   -- Can this item be purchased? (Overrides type default)

    -- Image/Media
    main_image_url TEXT NULLABLE,
    additional_images JSONB NULLABLE, -- Array of URLs or more structured image data

    -- Custom Fields / Extended Attributes
    custom_attributes JSONB NULLABLE,       -- For industry-specific or user-defined fields

    -- Audit
    created_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT nomenclatures_company_item_code_unique UNIQUE (company_id, item_code) WHERE item_code IS NOT NULL AND item_code <> '',
    CONSTRAINT check_nomenclature_selling_price_consistency CHECK (
        ( (default_selling_price_inclusive_vat IS NOT NULL OR default_selling_price_exclusive_vat IS NOT NULL) AND
          default_selling_price_currency_id IS NOT NULL AND default_selling_price_vat_rule_id IS NOT NULL ) OR
        ( default_selling_price_inclusive_vat IS NULL AND default_selling_price_exclusive_vat IS NULL AND
          default_selling_price_currency_id IS NULL AND default_selling_price_vat_rule_id IS NULL )
    ),
    CONSTRAINT check_nomenclature_stockable_tracking CHECK (
      -- If nomenclature_type.is_stockable is FALSE, then inventory_tracking_type must be 'none'.
      -- This requires a join or a function to enforce properly at DB level.
      -- For now, this is an application-level or more complex DB constraint.
      -- Placeholder:
      TRUE
      -- Proper check would be more complex:
      -- NOT (EXISTS (SELECT 1 FROM public.nomenclature_types nt
      --              WHERE nt.id = nomenclature_type_id AND nt.is_stockable = FALSE)
      --      AND inventory_tracking_type <> 'none')
    )
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_nomenclatures_company_id ON public.nomenclatures(company_id);
CREATE INDEX IF NOT EXISTS idx_nomenclatures_item_code ON public.nomenclatures(company_id, item_code) WHERE item_code IS NOT NULL AND item_code <> '';
CREATE INDEX IF NOT EXISTS idx_nomenclatures_name ON public.nomenclatures(company_id, name); -- For searching by name within a company
CREATE INDEX IF NOT EXISTS idx_nomenclatures_nomenclature_type_id ON public.nomenclatures(nomenclature_type_id);
CREATE INDEX IF NOT EXISTS idx_nomenclatures_inventory_tracking_type ON public.nomenclatures(inventory_tracking_type);

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_nomenclatures_updated_at
    BEFORE UPDATE ON public.nomenclatures
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.nomenclatures IS 'Master catalog for all products, services, assets, and other definable items a company deals with.';
COMMENT ON COLUMN public.nomenclatures.company_id IS 'Each nomenclature definition is specific to a company.';
COMMENT ON COLUMN public.nomenclatures.item_code IS 'Optional unique internal code or SKU for the item within the company. Unique per company if provided.';
COMMENT ON COLUMN public.nomenclatures.name IS 'Primary display name of the nomenclature.';
COMMENT ON COLUMN public.nomenclatures.nomenclature_type_id IS 'FK to nomenclature_types, classifying the item (e.g., physical product, service).';
COMMENT ON COLUMN public.nomenclatures.base_unit_id IS 'The primary unit of measure for this nomenclature (e.g., for stock, sales, purchases).';
COMMENT ON COLUMN public.nomenclatures.inventory_tracking_type IS 'Defines how inventory is tracked for this nomenclature (none, quantity_only, batch_tracked, serial_tracked).';
COMMENT ON COLUMN public.nomenclatures.default_selling_price_inclusive_vat IS 'Default selling price for B2C/POS scenarios, inclusive of VAT. Fallback if no other pricing applies.';
COMMENT ON COLUMN public.nomenclatures.default_selling_price_exclusive_vat IS 'Default selling price exclusive of VAT. Can be derived from inclusive price and VAT rule, or set directly.';
COMMENT ON COLUMN public.nomenclatures.default_selling_price_currency_id IS 'Currency for the default selling prices.';
COMMENT ON COLUMN public.nomenclatures.default_selling_price_vat_rule_id IS 'Default VAT rule associated with the default selling prices. FK to vat_rules_and_exemptions.';
COMMENT ON COLUMN public.nomenclatures.estimated_default_cost_price IS 'Estimated or standard cost price. Actual costs are tracked on inventory_stock_items.';
COMMENT ON COLUMN public.nomenclatures.default_vat_rule_id IS 'Default VAT rule to be applied for this item in sales/purchase transactions if no other rule takes precedence. FK to vat_rules_and_exemptions.';
COMMENT ON COLUMN public.nomenclatures.is_active IS 'Indicates if this nomenclature can be used in new transactions.';
COMMENT ON COLUMN public.nomenclatures.is_sellable IS 'Indicates if this nomenclature item can be included in sales documents (overrides type default).';
COMMENT ON COLUMN public.nomenclatures.is_purchasable IS 'Indicates if this nomenclature item can be included in purchase documents (overrides type default).';
COMMENT ON COLUMN public.nomenclatures.custom_attributes IS 'JSONB field for storing user-defined or industry-specific attributes not covered by standard columns.';


-- ### `public.nomenclature_translations`
-- Stores translations for user-facing text fields of the nomenclatures table.
CREATE TABLE IF NOT EXISTS public.nomenclature_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nomenclature_id UUID NOT NULL REFERENCES public.nomenclatures(id) ON DELETE CASCADE,
    locale_id UUID NOT NULL REFERENCES public.locales(id) ON DELETE RESTRICT,
    translation JSONB NOT NULL,
    -- Example: {
    --   "name": "Translated Product Name",
    --   "description": "Translated detailed description of the product.",
    --   "custom_attributes": { "color_label": "Translated Color Label", "material_description": "Translated Material Info" }
    -- }
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT nomenclature_translations_nomenclature_locale_unique UNIQUE (nomenclature_id, locale_id)
);
CREATE OR REPLACE TRIGGER set_public_nomenclature_translations_updated_at
    BEFORE UPDATE ON public.nomenclature_translations
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.nomenclature_translations IS 'Stores translations for user-facing text fields of the nomenclatures table using a flexible JSONB structure.';
COMMENT ON COLUMN public.nomenclature_translations.nomenclature_id IS 'Reference to the nomenclature being translated.';
COMMENT ON COLUMN public.nomenclature_translations.locale_id IS 'Reference to the locale for this translation.';
COMMENT ON COLUMN public.nomenclature_translations.translation IS 'JSONB object containing key-value pairs of translated fields. Keys should match field names or defined translation keys from the parent nomenclatures table (e.g., "name", "description").';

-- #############################################################################
-- # C. Document Numbering System
-- #############################################################################
-- Centralized system for generating formatted, sequential document numbers.

-- ## C.1. Core Table for Document Numbering

-- ### `public.document_sequence_definitions`
-- This table stores the definition and current state for each logical document numbering sequence.
CREATE TABLE IF NOT EXISTS public.document_sequence_definitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_location_id UUID NOT NULL REFERENCES public.company_locations(id) ON DELETE RESTRICT,
    sequence_type_key TEXT NOT NULL,    -- e.g., 'FISCAL_DOCUMENTS', 'SALES_ORDERS', 'PROFORMA_INVOICES', etc.
    prefix TEXT NULLABLE,               -- e.g., 'INV-', 'SO-'
    suffix TEXT NULLABLE,               -- e.g., '/{YYYY}' or '/24' (dynamic year replacement is app/function logic)
    start_number BIGINT NOT NULL DEFAULT 1,
    current_number BIGINT NOT NULL DEFAULT 0, -- The last number successfully issued. Initialized to start_number - increment_by.
    increment_by INTEGER NOT NULL DEFAULT 1 CHECK (increment_by > 0),
    padding_length INTEGER NOT NULL DEFAULT 0 CHECK (padding_length >= 0 AND padding_length <= 20), -- Max 20 for sanity.
    allow_periodic_reset BOOLEAN NOT NULL DEFAULT FALSE, -- True if this sequence type can be reset (e.g., annually)
    last_reset_date DATE NULLABLE,      -- Date the sequence was last reset (if allow_periodic_reset is true)
    is_active BOOLEAN NOT NULL DEFAULT TRUE, -- Allows deactivation of a sequence
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT document_sequence_definitions_location_type_key UNIQUE (company_location_id, sequence_type_key)
);
CREATE OR REPLACE TRIGGER set_public_document_sequence_definitions_updated_at
    BEFORE UPDATE ON public.document_sequence_definitions
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.document_sequence_definitions IS 'Defines and manages document numbering sequences, scoped per company location and sequence type.';
COMMENT ON COLUMN public.document_sequence_definitions.company_location_id IS 'The company location to which this numbering sequence applies.';
COMMENT ON COLUMN public.document_sequence_definitions.sequence_type_key IS 'Programmatic identifier for the type of sequence (e.g., "FISCAL_DOCUMENTS", "SALES_ORDERS").';
COMMENT ON COLUMN public.document_sequence_definitions.prefix IS 'Optional prefix string for the generated document number (e.g., "INV-").';
COMMENT ON COLUMN public.document_sequence_definitions.suffix IS 'Optional suffix string for the generated document number (e.g., "/2024"). Dynamic elements like year require function logic.';
COMMENT ON COLUMN public.document_sequence_definitions.start_number IS 'The conceptual first number for this sequence (e.g., 1, or 15001 for migrations).';
COMMENT ON COLUMN public.document_sequence_definitions.current_number IS 'The last numeric value that was successfully generated and committed for this sequence. For a new sequence starting at N with increment I, this should be initialized to N-I.';
COMMENT ON COLUMN public.document_sequence_definitions.increment_by IS 'The value to increment the current_number by for each new document number (typically 1).';
COMMENT ON COLUMN public.document_sequence_definitions.padding_length IS 'Desired total length of the numeric part, padded with leading zeros (e.g., 10 for "0000000001"). 0 means no padding.';
COMMENT ON COLUMN public.document_sequence_definitions.allow_periodic_reset IS 'Flag indicating if this sequence type is eligible for periodic resets (e.g., annually).';
COMMENT ON COLUMN public.document_sequence_definitions.last_reset_date IS 'Records the date the sequence was last reset, used in conjunction with allow_periodic_reset.';
COMMENT ON COLUMN public.document_sequence_definitions.is_active IS 'Indicates if the sequence definition is currently active and can be used for generating numbers.';


-- ## C.2. Function for Document Number Generation

-- ### `public.get_next_document_number(p_company_location_id UUID, p_sequence_type_key TEXT)`
-- This function is responsible for atomically fetching and incrementing the next number
-- for a given sequence definition and formatting it.
CREATE OR REPLACE FUNCTION public.get_next_document_number(
    p_company_location_id UUID,
    p_sequence_type_key TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE -- Important: Modifies data, so not STABLE or IMMUTABLE
AS $$
DECLARE
    seq_def RECORD;
    next_num BIGINT;
    formatted_number TEXT;
    current_year_text TEXT; -- Changed from current_year to avoid conflict with potential keyword if any pg version has it
    effective_suffix TEXT;
BEGIN
    -- Attempt to lock the specific sequence definition row for the duration of this transaction block
    -- This ensures atomicity when multiple transactions request a number from the same sequence concurrently.
    SELECT *
    INTO seq_def
    FROM public.document_sequence_definitions def
    WHERE def.company_location_id = p_company_location_id
      AND def.sequence_type_key = p_sequence_type_key
      AND def.is_active = TRUE
    FOR UPDATE OF def; -- Lock only the selected row

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No active document sequence definition found for company_location_id [%] and sequence_type_key [%]', p_company_location_id, p_sequence_type_key;
    END IF;

    -- Periodic Reset Logic (Example for Annual Reset)
    IF seq_def.allow_periodic_reset THEN
        current_year_text := TO_CHAR(CURRENT_DATE, 'YYYY');
        -- Check if reset is due: no last_reset_date OR last_reset_date's year is less than current year.
        IF seq_def.last_reset_date IS NULL OR TO_CHAR(seq_def.last_reset_date, 'YYYY') < current_year_text THEN
            -- Reset is due
            seq_def.current_number := seq_def.start_number - seq_def.increment_by; -- Reset current_number
            seq_def.last_reset_date := date_trunc('year', CURRENT_DATE); -- Set to start of current year for consistency
            
            UPDATE public.document_sequence_definitions
            SET current_number = seq_def.current_number,
                last_reset_date = seq_def.last_reset_date,
                updated_at = now()
            WHERE id = seq_def.id;
            -- No need to RETURNING * INTO seq_def here as we've modified the local seq_def record variables that matter for number generation.
        END IF;
    END IF;

    -- Determine the next number
    next_num := seq_def.current_number + seq_def.increment_by;

    -- Ensure next_num is not below start_number (e.g., if start_number was manually increased after some numbers were issued,
    -- or if current_number somehow became too low due to manual error without a proper reset).
    IF next_num < seq_def.start_number THEN
        next_num := seq_def.start_number;
    END IF;

    -- Update the current number in the definition table
    UPDATE public.document_sequence_definitions
    SET current_number = next_num,
        updated_at = now()
    WHERE id = seq_def.id;

    -- Format the number
    IF seq_def.padding_length > 0 THEN
        formatted_number := LPAD(next_num::TEXT, seq_def.padding_length, '0');
    ELSE
        formatted_number := next_num::TEXT;
    END IF;

    IF seq_def.prefix IS NOT NULL AND seq_def.prefix <> '' THEN
        formatted_number := seq_def.prefix || formatted_number;
    END IF;

    effective_suffix := seq_def.suffix;
    -- Basic dynamic suffix replacement for year (can be expanded for {MM}, {DD} etc.)
    IF effective_suffix IS NOT NULL AND effective_suffix <> '' THEN
        effective_suffix := REPLACE(effective_suffix, '{YYYY}', TO_CHAR(CURRENT_DATE, 'YYYY'));
        effective_suffix := REPLACE(effective_suffix, '{YY}', TO_CHAR(CURRENT_DATE, 'YY'));
        -- Add more replacements as needed:
        -- effective_suffix := REPLACE(effective_suffix, '{MM}', TO_CHAR(CURRENT_DATE, 'MM'));
        -- effective_suffix := REPLACE(effective_suffix, '{DD}', TO_CHAR(CURRENT_DATE, 'DD'));
        formatted_number := formatted_number || effective_suffix;
    END IF;

    RETURN formatted_number;
END;
$$;

COMMENT ON FUNCTION public.get_next_document_number(UUID, TEXT) IS 'Generates the next formatted document number for a given company location and sequence type. It handles atomic incrementing using FOR UPDATE, formatting (padding, prefix, suffix with {YYYY}/{YY} replacement), and includes logic for periodic resets (e.g., annual). Example Usage: SELECT public.get_next_document_number(''location-uuid'', ''FISCAL_DOCUMENTS'');';


-- #############################################################################
-- # D. Subscriptions Module (Tenant-Facing)
-- #############################################################################
-- Entities for managing recurring subscriptions that tenant companies
-- offer to their own partners/customers.

-- ## D.1. ENUM Types for Tenant Subscriptions

-- ### `public.subscription_status_enum` (Tenant-Facing)
-- Defines the lifecycle states for a subscription contract a tenant company has with its partner.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'subscription_status_enum') THEN
        CREATE TYPE public.subscription_status_enum AS ENUM (
            'pending_initial_payment', -- New subscription, awaiting first payment to become active
            'active',                  -- Current, in good standing, generating invoices
            'past_due',                -- Payment for a generated invoice is overdue
            'paused',                  -- Temporarily suspended by user or admin (no new invoices generated)
            'cancelled',               -- Terminated by user or admin, will not renew, no new invoices
            'expired',                 -- Reached its end_date and was not auto-renewed
            'incomplete'               -- Setup started but not fully configured/activated (e.g., missing payment method)
        );
        COMMENT ON TYPE public.subscription_status_enum IS 'Defines the lifecycle states for a subscription contract a tenant company has with its partner.';
    END IF;
END$$;


-- ## D.2. Core Table for Tenant Subscriptions

-- ### `public.subscriptions`
-- Manages recurring service agreements (subscriptions) that Hyper M v2 tenant companies
-- have with their own partners/customers.
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT, -- The Hyper M v2 tenant company owning this subscription contract
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE RESTRICT,   -- The partner/customer subscribing to the service

    nomenclature_id UUID NULLABLE REFERENCES public.nomenclatures(id) ON DELETE SET NULL, -- Original plan/template from nomenclatures, can be NULL if fully custom or if original plan is deleted.
                                                                                        -- This nomenclature should be of a type like 'SUBSCRIPTION_PLAN'.

    -- Subscription Contract Details
    name TEXT NOT NULL,                                          -- User-friendly name/title for this specific subscription contract (e.g., "Premium SaaS Access - Contoso Corp")
    contract_details TEXT NULLABLE,                              -- For contract-specific details (e.g., contract number, signed date, specific terms, notes)

    -- Pricing & Currency (Contractual - can be overridden from nomenclature)
    currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT,
    price_exclusive_vat NUMERIC(15, 5) NOT NULL,
    vat_amount NUMERIC(15, 5) NOT NULL,                          -- The VAT amount based on price_exclusive_vat and expected_billing_vat_rate_percentage
    price_inclusive_vat NUMERIC(15, 5) NOT NULL,                 -- Should always be price_exclusive_vat + vat_amount

    -- Expected VAT Treatment (for this partner and subscription - an estimate, invoice is authoritative)
    expected_billing_vat_rate_percentage NUMERIC(5, 2) NOT NULL DEFAULT 0.00, -- e.g., 20.00, 9.00, 0.00
    expected_billing_vat_rule_id UUID NULLABLE REFERENCES public.vat_rules_and_exemptions(id) ON DELETE SET NULL, -- FK to vat_rules_and_exemptions. Defined in Invoicing Module DDLs.
                                                                                                                 -- Storing rule_id is better than free text for consistency.

    -- Billing Cycle & Dates
    status public.subscription_status_enum NOT NULL DEFAULT 'incomplete',
    start_date DATE NOT NULL,                                    -- Date the subscription contract becomes active or first billing period starts
    end_date DATE NULLABLE,                                      -- Date the subscription contract definitively ends (if not auto-renewing or cancelled)
    billing_interval_months INTEGER NOT NULL CHECK (billing_interval_months > 0), -- e.g., 1 (monthly), 3 (quarterly), 12 (annually)
    last_billed_date DATE NULLABLE,                              -- The end date of the last period for which an invoice was successfully generated
    next_billing_date DATE NULLABLE,                             -- The start date of the next period to be billed (crucial for automation)

    -- Settings & Flags
    auto_renews BOOLEAN NOT NULL DEFAULT TRUE,
    is_prepaid BOOLEAN NOT NULL DEFAULT FALSE,                   -- If the subscription cycle is paid in advance
    invoice_period_display_short BOOLEAN NOT NULL DEFAULT TRUE,  -- True for "for MM.YYYY", False for "from DD.MM.YYYY to DD.MM.YYYY" on invoices

    -- Audit & Timestamps
    created_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL, -- User in the tenant company who created this subscription
    activated_at TIMESTAMP WITH TIME ZONE NULLABLE,              -- Timestamp when status first became 'active' or 'pending_initial_payment'
    cancelled_at TIMESTAMP WITH TIME ZONE NULLABLE,              -- Timestamp when status became 'cancelled'
    paused_at TIMESTAMP WITH TIME ZONE NULLABLE,                 -- Timestamp when status became 'paused'
    expired_at TIMESTAMP WITH TIME ZONE NULLABLE,                -- Timestamp when status became 'expired' (if applicable)
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT check_subscriptions_prices_consistency CHECK (ROUND(price_inclusive_vat, 5) = ROUND(price_exclusive_vat + vat_amount, 5)),
    CONSTRAINT check_subscriptions_dates_logic CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT check_subscriptions_next_billing_date_for_active CHECK (
        (status IN ('active', 'pending_initial_payment') AND next_billing_date IS NOT NULL) OR
        (status NOT IN ('active', 'pending_initial_payment')) -- next_billing_date can be NULL for other statuses
    )
);
CREATE INDEX IF NOT EXISTS idx_subscriptions_company_id ON public.subscriptions(company_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_partner_id ON public.subscriptions(partner_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_next_billing_date ON public.subscriptions(next_billing_date);
CREATE INDEX IF NOT EXISTS idx_subscriptions_auto_renews ON public.subscriptions(auto_renews);
CREATE INDEX IF NOT EXISTS idx_subscriptions_nomenclature_id ON public.subscriptions(nomenclature_id);

CREATE OR REPLACE TRIGGER set_public_subscriptions_updated_at
    BEFORE UPDATE ON public.subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.subscriptions IS 'Manages recurring service agreements (subscriptions) that tenant companies offer to their partners, including contractual pricing, billing cycles, and status.';
COMMENT ON COLUMN public.subscriptions.company_id IS 'The Hyper M v2 tenant company that owns and manages this subscription contract.';
COMMENT ON COLUMN public.subscriptions.partner_id IS 'The partner (customer) of the tenant company who is subscribed to the service.';
COMMENT ON COLUMN public.subscriptions.nomenclature_id IS 'Reference to the original nomenclature (subscription plan/template defined by the tenant) this subscription was based on. Can be NULL if fully custom or if original plan is deleted.';
COMMENT ON COLUMN public.subscriptions.name IS 'User-friendly name or title for this specific subscription contract (e.g., "Gold Support Plan - Acme Corp").';
COMMENT ON COLUMN public.subscriptions.contract_details IS 'Stores contract-specific information like contract number, signed date, or special terms relevant to the tenant and their partner.';
COMMENT ON COLUMN public.subscriptions.price_exclusive_vat IS 'Contractual base price per billing cycle, excluding VAT, charged by the tenant to their partner.';
COMMENT ON COLUMN public.subscriptions.vat_amount IS 'Contractual VAT amount per billing cycle, based on price_exclusive_vat and expected_billing_vat_rate_percentage.';
COMMENT ON COLUMN public.subscriptions.price_inclusive_vat IS 'Contractual total price per billing cycle, including VAT, charged by the tenant to their partner.';
COMMENT ON COLUMN public.subscriptions.expected_billing_vat_rate_percentage IS 'The VAT rate percentage the tenant expects to apply for their partner for this subscription. Invoice is authoritative.';
COMMENT ON COLUMN public.subscriptions.expected_billing_vat_rule_id IS 'The VAT rule the tenant expects to apply. FK to vat_rules_and_exemptions. Invoice is authoritative.';
COMMENT ON COLUMN public.subscriptions.status IS 'Current lifecycle state of the subscription between the tenant and their partner.';
COMMENT ON COLUMN public.subscriptions.start_date IS 'Date the subscription contractually starts or the first billing period begins for the partner.';
COMMENT ON COLUMN public.subscriptions.end_date IS 'Date the subscription contractually ends for the partner. NULL if open-ended or auto-renewing until cancelled.';
COMMENT ON COLUMN public.subscriptions.billing_interval_months IS 'Number of months in one billing cycle for this subscription (e.g., 1 for monthly, 3 for quarterly).';
COMMENT ON COLUMN public.subscriptions.last_billed_date IS 'The end date of the service period covered by the last successfully generated invoice to the partner.';
COMMENT ON COLUMN public.subscriptions.next_billing_date IS 'The start date of the next service period to be billed to the partner. Drives tenant''s invoice generation.';
COMMENT ON COLUMN public.subscriptions.auto_renews IS 'If true, the subscription will attempt to renew at the end of its current billing cycle (if not ended/cancelled).';
COMMENT ON COLUMN public.subscriptions.is_prepaid IS 'Indicates if the partner pays for the subscription cycle in advance.';
COMMENT ON COLUMN public.subscriptions.invoice_period_display_short IS 'Preference for displaying the billing period on invoices generated by the tenant for this subscription (True for "for MM.YYYY", False for "from DD.MM.YYYY to DD.MM.YYYY").';
COMMENT ON COLUMN public.subscriptions.created_by_user_id IS 'The user within the tenant company who created or last managed this subscription record.';
COMMENT ON COLUMN public.subscriptions.activated_at IS 'Timestamp when the subscription first became active or pending initial payment for the partner.';
COMMENT ON COLUMN public.subscriptions.cancelled_at IS 'Timestamp when the subscription with the partner was cancelled.';
COMMENT ON COLUMN public.subscriptions.paused_at IS 'Timestamp when the subscription with the partner was paused.';
COMMENT ON COLUMN public.subscriptions.expired_at IS 'Timestamp when a non-renewing subscription with the partner reached its end_date and moved to expired status.';


-- #############################################################################
-- # E. Sales & Ordering Module
-- #############################################################################
-- Entities for managing sales quotes (conceptual), sales orders, and their items.

-- ## E.1. ENUM Types for Sales & Ordering

-- ### `public.sales_order_status_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sales_order_status_enum') THEN
        CREATE TYPE public.sales_order_status_enum AS ENUM (
            'draft',                            -- Order created, not yet finalized or submitted
            'pending_approval',                 -- Submitted for internal approval before confirmation
            'awaiting_partner_confirmation',    -- Sent to partner, awaiting their acceptance/PO
            'confirmed',                        -- Confirmed by partner and/or internally, ready for fulfillment/invoicing
            'partially_fulfilled',              -- Some items/quantities have been dispatched/delivered
            'fully_fulfilled',                  -- All items/quantities have been dispatched/delivered
            'partially_invoiced',               -- Some fulfilled items/quantities have been invoiced
            'fully_invoiced',                   -- All fulfilled items/quantities have been invoiced
            'completed',                        -- Typically means fully fulfilled AND fully invoiced (and often implies paid for non-POS)
            'on_hold',                          -- Order processing is temporarily suspended
            'cancelled'                         -- Order cancelled before completion
        );
        COMMENT ON TYPE public.sales_order_status_enum IS 'Defines the lifecycle states of a sales order.';
    END IF;
END$$;

-- ### `public.order_item_fulfillment_status_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_item_fulfillment_status_enum') THEN
        CREATE TYPE public.order_item_fulfillment_status_enum AS ENUM (
            'pending_fulfillment',      -- Default, awaiting action (e.g., stock check, allocation)
            'awaiting_allocation',      -- Fulfillment process started, stock needs to be allocated
            'partially_allocated',      -- Some required stock has been allocated/reserved
            'fully_allocated',          -- All required stock has been allocated/reserved
            'ready_for_dispatch',       -- Allocated and ready to be picked/packed/shipped
            'partially_fulfilled',      -- Part of the ordered quantity has been shipped/delivered/service rendered
            'fully_fulfilled',          -- The entire ordered quantity has been shipped/delivered/service rendered
            'on_hold'                   -- Fulfillment for this specific item is temporarily suspended
        );
        COMMENT ON TYPE public.order_item_fulfillment_status_enum IS 'Defines the various stages of fulfillment for a sales order line item.';
    END IF;
END$$;


-- ## E.2. Core Tables for Sales & Ordering
-- Note: public.quotes and public.quote_items are conceptual for future definition and not included here yet.

-- ### `public.sales_orders`
-- Represents confirmed sales orders from partners, detailing items/services to be provided.
-- Can represent various order types like standard B2B, POS, or e-commerce.
CREATE TABLE IF NOT EXISTS public.sales_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    company_location_id UUID NOT NULL REFERENCES public.company_locations(id) ON DELETE RESTRICT, -- Location managing/fulfilling the order
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE RESTRICT,

    -- Partner Details Snapshot (for integrity of order-time partner info)
    partner_details JSONB NOT NULL,
        -- Snapshot: {"name": "Partner Corp", "vat_id": "BG123456789", "eik": "...", "contact_person": "...", "email": "..."}

    -- Order Identification & Dates
    order_number TEXT NOT NULL, -- Generated using document_sequence_definitions(sequence_type_key='SALES_ORDERS' or 'POS_ORDERS')
    order_date DATE NOT NULL DEFAULT CURRENT_DATE,
    order_type_key TEXT NOT NULL DEFAULT 'STANDARD', -- e.g., 'STANDARD', 'POS_TRANSACTION', 'ECOMMERCE'. Could FK to a future sales_order_types(key) table.
    requested_delivery_date DATE NULLABLE,
    confirmed_delivery_date DATE NULLABLE,
    actual_delivery_date DATE NULLABLE, -- Actual final delivery date of the entire order (if applicable at header)

    -- Source of Order
    -- source_quote_id UUID NULLABLE, -- FK to public.quotes(id) to be added later
    external_order_reference TEXT NULLABLE, -- e.g., Partner's PO number, e-commerce order ID

    -- Addresses
    shipping_address_details JSONB NULLABLE, -- Snapshot of shipping address (can be from partner or custom for this order)
    billing_address_details JSONB NULLABLE,  -- Snapshot of billing address

    -- Currency & Provisional Totals (Derived from sales_order_items)
    currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT,
    estimated_total_exclusive_vat NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    estimated_total_vat_amount NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    estimated_total_inclusive_vat NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,

    -- Status & Control
    status public.sales_order_status_enum NOT NULL DEFAULT 'draft',
    assigned_sales_rep_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL, -- User within the tenant company
    payment_terms_id UUID NULLABLE REFERENCES public.payment_terms(id) ON DELETE SET NULL, -- Defined in Invoicing Module DDLs

    -- Notes
    notes_to_partner TEXT NULLABLE,
    internal_notes TEXT NULLABLE,

    -- Audit
    created_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL, -- User within the tenant company
    cancelled_at TIMESTAMP WITH TIME ZONE NULLABLE,
    cancellation_reason TEXT NULLABLE,
    cancellation_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL, -- User who cancelled
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT sales_orders_company_location_order_number_key UNIQUE (company_location_id, order_number),
    CONSTRAINT check_sales_order_cancellation_details CHECK (
        (status = 'cancelled' AND cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND cancellation_user_id IS NOT NULL) OR
        (status <> 'cancelled' AND cancelled_at IS NULL AND cancellation_reason IS NULL AND cancellation_user_id IS NULL)
    ),
    CONSTRAINT check_sales_order_estimated_totals CHECK (
        ROUND(estimated_total_inclusive_vat, 5) = ROUND(estimated_total_exclusive_vat + estimated_total_vat_amount, 5)
    )
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_sales_orders_company_id ON public.sales_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_orders_partner_id ON public.sales_orders(partner_id);
CREATE INDEX IF NOT EXISTS idx_sales_orders_order_number ON public.sales_orders(company_location_id, order_number); -- Composite for lookup
CREATE INDEX IF NOT EXISTS idx_sales_orders_order_date ON public.sales_orders(order_date);
CREATE INDEX IF NOT EXISTS idx_sales_orders_status ON public.sales_orders(status);
CREATE INDEX IF NOT EXISTS idx_sales_orders_assigned_sales_rep_id ON public.sales_orders(assigned_sales_rep_id);
CREATE INDEX IF NOT EXISTS idx_sales_orders_order_type_key ON public.sales_orders(order_type_key);

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_sales_orders_updated_at
    BEFORE UPDATE ON public.sales_orders
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.sales_orders IS 'Represents sales orders from partners, detailing items/services to be provided. Can be B2B, POS, etc.';
COMMENT ON COLUMN public.sales_orders.company_location_id IS 'The company location primarily responsible for this sales order.';
COMMENT ON COLUMN public.sales_orders.partner_details IS 'Immutable JSON snapshot of key partner details (name, identifiers, contacts) at the time of order placement.';
COMMENT ON COLUMN public.sales_orders.order_number IS 'Unique sales order number, generated per company_location_id.';
COMMENT ON COLUMN public.sales_orders.order_type_key IS 'Identifies the type or channel of the sales order (e.g., ''STANDARD'', ''POS_TRANSACTION''). Drives specific business logic.';
COMMENT ON COLUMN public.sales_orders.shipping_address_details IS 'JSON snapshot of the shipping address for this order.';
COMMENT ON COLUMN public.sales_orders.billing_address_details IS 'JSON snapshot of the billing address for this order.';
COMMENT ON COLUMN public.sales_orders.estimated_total_exclusive_vat IS 'Sum of line totals exclusive of VAT, in order currency. Calculated from items.';
COMMENT ON COLUMN public.sales_orders.estimated_total_vat_amount IS 'Sum of estimated line VAT amounts, in order currency. Calculated from items.';
COMMENT ON COLUMN public.sales_orders.estimated_total_inclusive_vat IS 'Total estimated order value inclusive of VAT, in order currency. Calculated from items.';
COMMENT ON COLUMN public.sales_orders.payment_terms_id IS 'FK to payment_terms defining payment conditions for this order.';
COMMENT ON COLUMN public.sales_orders.cancellation_user_id IS 'User who performed the cancellation of the sales order.';


-- ### `public.sales_order_items`
-- Stores individual line items for sales orders, detailing products/services ordered,
-- provisional pricing, and fulfillment status.
CREATE TABLE IF NOT EXISTS public.sales_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sales_order_id UUID NOT NULL REFERENCES public.sales_orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT, -- Denormalized for RLS

    -- Item Identification & Description (Can be overridden from nomenclature)
    nomenclature_id UUID NULLABLE REFERENCES public.nomenclatures(id) ON DELETE SET NULL,
    item_description TEXT NOT NULL, -- Description as it appears on the sales order
    item_serial_number_selection_details TEXT NULLABLE, -- For noting requested serials or simple tracking at order stage
    item_batch_number_selection_details TEXT NULLABLE,  -- For noting requested batches or simple tracking at order stage

    -- Quantity & Unit
    quantity_ordered NUMERIC(15, 5) NOT NULL,
    unit_id UUID NOT NULL REFERENCES public.nomenclature_unit(id) ON DELETE RESTRICT,

    -- Provisional Pricing (Per Unit, in sales order's currency)
    original_unit_price_exclusive_vat NUMERIC(15, 5) NULLABLE, -- List price before order-specifics
    unit_price_exclusive_vat NUMERIC(15, 5) NOT NULL,         -- Agreed price per unit for this line
    discount_percentage NUMERIC(5, 2) NULLABLE DEFAULT 0.00 CHECK (discount_percentage IS NULL OR (discount_percentage >= -100 AND discount_percentage <= 100)),
    discount_amount_per_unit NUMERIC(15, 5) NULLABLE DEFAULT 0.00000,

    -- Provisional Line Totals (Calculated, in sales order's currency)
    line_total_exclusive_vat NUMERIC(15, 5) NOT NULL,
    estimated_line_vat_amount NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    line_total_inclusive_vat NUMERIC(15, 5) NOT NULL,

    -- Provisional VAT Treatment (Estimate, final determination at invoicing)
    estimated_vat_rule_id UUID NULLABLE REFERENCES public.vat_rules_and_exemptions(id) ON DELETE SET NULL, -- Defined in Invoicing Module
    estimated_vat_rate_percentage NUMERIC(5, 2) NULLABLE,

    -- Fulfillment & Invoicing Tracking
    quantity_allocated NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    quantity_fulfilled NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    quantity_invoiced NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    quantity_credited NUMERIC(15,5) NOT NULL DEFAULT 0.00000, -- Quantity from this SO line that was credited
    fulfillment_status public.order_item_fulfillment_status_enum NOT NULL DEFAULT 'pending_fulfillment',

    -- Delivery Information (Per-line specifics if needed)
    requested_delivery_date DATE NULLABLE,
    confirmed_delivery_date DATE NULLABLE,

    -- Bundle Information
    is_bundle_component BOOLEAN NOT NULL DEFAULT FALSE,
    bundle_parent_item_id UUID NULLABLE REFERENCES public.sales_order_items(id) ON DELETE SET NULL, -- Self-reference to parent bundle item

    -- Additional Dynamic Data
    item_metadata JSONB NULLABLE, -- e.g., selected product options, custom configurations

    -- Display & Ordering
    display_order INTEGER NOT NULL DEFAULT 0,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT check_so_item_quantity_ordered_positive CHECK (quantity_ordered > 0),
    CONSTRAINT check_so_item_fulfillment_quantities CHECK (
        quantity_allocated >= 0 AND quantity_allocated <= quantity_ordered AND
        quantity_fulfilled >= 0 AND quantity_fulfilled <= quantity_allocated AND -- Typically fulfill from allocated
        quantity_invoiced >= 0 AND quantity_invoiced <= quantity_fulfilled AND
        quantity_credited >= 0 AND quantity_credited <= quantity_invoiced -- Credited qty cannot exceed invoiced qty for this SO line
    ),
    CONSTRAINT check_so_item_line_totals_consistency CHECK (
        ROUND(line_total_inclusive_vat, 5) = ROUND(line_total_exclusive_vat + estimated_line_vat_amount, 5)
    ),
    CONSTRAINT check_so_item_bundle_logic CHECK (
        (is_bundle_component = TRUE AND bundle_parent_item_id IS NOT NULL) OR
        (is_bundle_component = FALSE AND bundle_parent_item_id IS NULL)
    ),
    CONSTRAINT check_so_item_bundle_parent_is_not_self CHECK (id <> bundle_parent_item_id OR bundle_parent_item_id IS NULL)
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_sales_order_items_sales_order_id ON public.sales_order_items(sales_order_id);
CREATE INDEX IF NOT EXISTS idx_sales_order_items_company_id ON public.sales_order_items(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_order_items_nomenclature_id ON public.sales_order_items(nomenclature_id);
CREATE INDEX IF NOT EXISTS idx_sales_order_items_bundle_parent_item_id ON public.sales_order_items(bundle_parent_item_id) WHERE is_bundle_component = TRUE;
CREATE INDEX IF NOT EXISTS idx_sales_order_items_fulfillment_status ON public.sales_order_items(fulfillment_status);

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_sales_order_items_updated_at
    BEFORE UPDATE ON public.sales_order_items
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.sales_order_items IS 'Stores individual line items for sales orders, detailing products/services, provisional pricing, and fulfillment/invoicing status. All monetary values are in the currency of the parent sales order.';
COMMENT ON COLUMN public.sales_order_items.item_description IS 'Description of the item/service as it appears on the sales order. Can be from nomenclature or customized.';
COMMENT ON COLUMN public.sales_order_items.item_serial_number_selection_details IS 'Text field for noting customer-requested serial numbers or simple tracking/notes related to serials at the order stage.';
COMMENT ON COLUMN public.sales_order_items.item_batch_number_selection_details IS 'Text field for noting customer-requested batch numbers or simple tracking/notes related to batches at the order stage.';
COMMENT ON COLUMN public.sales_order_items.original_unit_price_exclusive_vat IS 'The original or list price per unit before any order-specific pricing, discounts or overrides. For reference.';
COMMENT ON COLUMN public.sales_order_items.unit_price_exclusive_vat IS 'Agreed/quoted price per unit for this order line, excluding VAT, in order currency.';
COMMENT ON COLUMN public.sales_order_items.discount_percentage IS 'Percentage discount applied to this line item (e.g., 10.00 for 10%). Can be negative for markup.';
COMMENT ON COLUMN public.sales_order_items.line_total_exclusive_vat IS 'Provisional total amount for this line, excluding VAT, after all discounts. (Calculated field).';
COMMENT ON COLUMN public.sales_order_items.estimated_line_vat_amount IS 'Estimated VAT amount for this line. Final VAT is determined at invoicing.';
COMMENT ON COLUMN public.sales_order_items.estimated_vat_rule_id IS 'Estimated VAT rule applicable to this line item at order time. FK to vat_rules_and_exemptions.';
COMMENT ON COLUMN public.sales_order_items.quantity_allocated IS 'Quantity of this item allocated/reserved from available stock specifically for this order line.';
COMMENT ON COLUMN public.sales_order_items.quantity_fulfilled IS 'Quantity of this item that has been shipped/delivered/service rendered against this order line.';
COMMENT ON COLUMN public.sales_order_items.quantity_invoiced IS 'Quantity of this item (from fulfilled quantity) that has already been included in an invoice.';
COMMENT ON COLUMN public.sales_order_items.quantity_credited IS 'Quantity of this item (from invoiced quantity) that has been subsequently credited via credit notes related to this sales order line or its invoiced counterparts.';
COMMENT ON COLUMN public.sales_order_items.fulfillment_status IS 'Tracks the fulfillment stage of this specific order line.';
COMMENT ON COLUMN public.sales_order_items.is_bundle_component IS 'True if this line item is a component of a larger bundle defined on another line item in this sales order.';
COMMENT ON COLUMN public.sales_order_items.bundle_parent_item_id IS 'If is_bundle_component is true, this references the id of the primary bundle item line in this same sales_order_items table.';
COMMENT ON COLUMN public.sales_order_items.item_metadata IS 'JSONB field for storing custom attributes, configurations, or other dynamic data specific to this sales order line item.';


-- #############################################################################
-- # F. Invoicing & Financial Documents Module
-- #############################################################################
-- Entities for invoices, credit notes, debit notes, and related lookups.

-- ## F.1. ENUM Types for Invoicing

-- ### `public.invoice_status_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'invoice_status_enum') THEN
        CREATE TYPE public.invoice_status_enum AS ENUM (
            'draft',             -- Document created, not yet finalized or issued
            'pending_approval',  -- (Optional) If an approval workflow is needed before issuance
            'issued',            -- Document finalized and sent to partner, awaiting payment (for invoices/debit notes) or application (for credit notes)
            'partially_paid',    -- Partial payment received (applies to invoices/debit notes)
            'paid',              -- Full payment received (applies to invoices/debit notes)
            'overdue',           -- Payment past due date (applies to invoices/debit notes)
            'voided',            -- Document cancelled after issuance (e.g., error, never sent)
            'applied'            -- Credit note fully applied to invoices or refunded (specific to credit notes)
        );
        COMMENT ON TYPE public.invoice_status_enum IS 'Defines the lifecycle and payment/application states of an invoice, credit note, or debit note.';
    END IF;
END$$;

-- ### `public.invoice_vat_summary_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'invoice_vat_summary_enum') THEN
        CREATE TYPE public.invoice_vat_summary_enum AS ENUM (
            'standard_vat_applied',         -- Standard VAT rate(s) applied
            'mixed_vat_rates_applied',      -- Different VAT rates applied (std, reduced, zero)
            'fully_zero_rated_export',      -- All items zero-rated due to export
            'fully_zero_rated_intra_community', -- All items zero-rated due to intra-community supply (B2B)
            'fully_zero_rated_oss',         -- All items subject to OSS VAT in destination country
            'fully_zero_rated_issuer_not_registered', -- All items zero-rated as issuer is not VAT registered
            'fully_zero_rated_other',       -- All items zero-rated for other specific reasons (e.g., specific domestic exemptions)
            'reverse_charge_applicable',    -- Entire invoice (or significant portion) subject to reverse charge
            'vat_treatment_complex'         -- Other complex scenarios not easily summarized (e.g., margin schemes)
        );
        COMMENT ON TYPE public.invoice_vat_summary_enum IS 'Provides a high-level summary of the overall VAT treatment for an invoice, credit, or debit note, derived from its line items and context.';
    END IF;
END$$;


-- ## F.2. Lookup Tables for Invoicing

-- ### `public.payment_methods`
-- Lookup table for payment methods. Can be global (company_id IS NULL) or company-specific.
CREATE TABLE IF NOT EXISTS public.payment_methods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NULLABLE REFERENCES public.companies(id) ON DELETE CASCADE,
    key TEXT NOT NULL,                  -- e.g., 'bank_transfer', 'cash', 'card_pos', 'paypal', 'stripe_online'
    name TEXT NOT NULL,                 -- e.g., "Bank Transfer", "Cash Payment", "Card (POS)"
    description TEXT NULLABLE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    requires_fiscalization BOOLEAN NOT NULL DEFAULT FALSE, -- True for 'cash', 'card_pos' in some jurisdictions
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT payment_methods_company_key_unique UNIQUE (company_id, key),
    CONSTRAINT payment_methods_global_key_unique UNIQUE (key) WHERE company_id IS NULL
);
CREATE OR REPLACE TRIGGER set_public_payment_methods_updated_at
    BEFORE UPDATE ON public.payment_methods
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.payment_methods IS 'Lookup table for payment methods. Can be global (company_id IS NULL) or company-specific.';
COMMENT ON COLUMN public.payment_methods.company_id IS 'If NULL, this payment method is a global system default. If set, it''s specific to a company.';
COMMENT ON COLUMN public.payment_methods.key IS 'Short, unique programmatic key for the payment method.';
COMMENT ON COLUMN public.payment_methods.requires_fiscalization IS 'Indicates if transactions with this payment method typically require fiscal receipt generation in certain jurisdictions.';

-- ### `public.payment_terms`
-- Lookup table for payment terms. Can be global (company_id IS NULL) or company-specific.
CREATE TABLE IF NOT EXISTS public.payment_terms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NULLABLE REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,                 -- e.g., "Net 30", "Due on Receipt", "15 Days End of Month"
    description TEXT NULLABLE,
    due_days INTEGER NULLABLE,          -- Number of days from invoice issue_date until due.
    -- due_day_of_month INTEGER NULLABLE, -- For terms like "15th of following month"
    -- due_months_offset INTEGER NULLABLE, -- For terms like "End of Next Month"
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT payment_terms_company_name_unique UNIQUE (company_id, name),
    CONSTRAINT payment_terms_global_name_unique UNIQUE (name) WHERE company_id IS NULL
    -- Add CHECK constraint for due_days, due_day_of_month, due_months_offset logic if complex terms are modeled with more fields.
);
CREATE OR REPLACE TRIGGER set_public_payment_terms_updated_at
    BEFORE UPDATE ON public.payment_terms
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.payment_terms IS 'Lookup table for payment terms (e.g., Net 30, Due on Receipt). Can be global or company-specific.';
COMMENT ON COLUMN public.payment_terms.company_id IS 'If NULL, these payment terms are a global system default. If set, they are specific to a company.';
COMMENT ON COLUMN public.payment_terms.name IS 'User-friendly name for the payment term (e.g., "Net 30 Days").';
COMMENT ON COLUMN public.payment_terms.due_days IS 'Number of days from invoice issue date until it is due. Can be NULL for complex terms not based on simple day count.';


-- ### `public.vat_rules_and_exemptions`
-- Defines VAT rules, applicable rates, and exemption reasons for invoice line items.
-- Can be global (company_id IS NULL) or company-specific.
CREATE TABLE IF NOT EXISTS public.vat_rules_and_exemptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NULLABLE REFERENCES public.companies(id) ON DELETE CASCADE,
    rule_code TEXT NOT NULL,            -- e.g., "DOMESTIC_STD_20", "EXPORT_GOODS_ART39", "EU_RCH_SERVICES_ART44", "ZERO_RATE_DOM_EXEMPT"
    description TEXT NOT NULL,          -- User-friendly description of the rule or exemption
    legal_basis_reference TEXT NULLABLE,-- e.g., "Art. 39 ZDDS", "Art. 44 EU VAT Directive 2006/112/EC"
    applies_to_country_code TEXT NULLABLE REFERENCES public.countries(code) ON DELETE RESTRICT, -- If rule is country-specific (e.g., specific domestic 0% rate)
    vat_rate_percentage NUMERIC(5,2) NOT NULL CHECK (vat_rate_percentage >= 0 AND vat_rate_percentage <= 100), -- The VAT rate this rule implies (e.g., 20.00, 9.00, 0.00)
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    fiscal_vat_group_id UUID NULLABLE REFERENCES public.fiscal_vat_groups(id) ON DELETE SET NULL, -- Optional link to fiscal printer VAT group
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT vat_rules_company_code_unique UNIQUE (company_id, rule_code),
    CONSTRAINT vat_rules_global_code_unique UNIQUE (rule_code) WHERE company_id IS NULL
);
CREATE OR REPLACE TRIGGER set_public_vat_rules_and_exemptions_updated_at
    BEFORE UPDATE ON public.vat_rules_and_exemptions
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.vat_rules_and_exemptions IS 'Defines VAT rules, applicable rates, and exemption reasons for financial document line items. Can be global or company-specific.';
COMMENT ON COLUMN public.vat_rules_and_exemptions.company_id IS 'If NULL, this rule is global. If set, it''s specific to a company.';
COMMENT ON COLUMN public.vat_rules_and_exemptions.rule_code IS 'Unique programmatic code identifying the VAT rule or exemption.';
COMMENT ON COLUMN public.vat_rules_and_exemptions.legal_basis_reference IS 'Reference to the legal article or basis for this VAT rule/exemption.';
COMMENT ON COLUMN public.vat_rules_and_exemptions.applies_to_country_code IS 'ISO code of the country this rule is particular to (e.g. a domestic zero rate). References countries.code.';
COMMENT ON COLUMN public.vat_rules_and_exemptions.vat_rate_percentage IS 'The actual VAT rate percentage this rule results in (e.g., 20.00, 0.00).';
COMMENT ON COLUMN public.vat_rules_and_exemptions.fiscal_vat_group_id IS 'Optional link to a fiscal_vat_groups record, if this VAT rule corresponds to a specific fiscal printer VAT group.';


-- ## F.3. Core Financial Document Tables

-- ### `public.invoices`
-- Represents issued invoices to partners. Header-level information for financial billing documents.
CREATE TABLE IF NOT EXISTS public.invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    company_location_id UUID NOT NULL REFERENCES public.company_locations(id) ON DELETE RESTRICT,
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE RESTRICT,
    document_number TEXT NOT NULL, -- Generated using document_sequence_definitions(sequence_type_key='FISCAL_DOCUMENTS' or specific 'INVOICES')
    issue_date DATE NOT NULL,
    tax_event_date DATE NOT NULL, -- Date determining VAT liability (aka "Дата на данъчно събитие")
    due_date DATE NULLABLE,       -- Calculated based on issue_date and payment_terms

    currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT,
    total_exclusive_vat NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    total_vat_amount NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    total_inclusive_vat NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,

    -- For multi-currency: amounts converted to company's default currency
    exchange_rate_to_company_default NUMERIC(15, 8) NULLABLE,
    total_exclusive_vat_company_default NUMERIC(15, 5) NULLABLE,
    total_vat_amount_company_default NUMERIC(15, 5) NULLABLE,
    total_inclusive_vat_company_default NUMERIC(15, 5) NULLABLE,

    vat_breakdown JSONB NULLABLE, -- Summary: {"20.00": {"base": 100, "vat": 20}, "0.00_EXPORT": {"base": 50, "vat": 0}}
    overall_vat_treatment_summary public.invoice_vat_summary_enum NULLABLE, -- Derived summary
    vies_check_id UUID NULLABLE REFERENCES public.vat_responses(id) ON DELETE SET NULL, -- If VIES check was performed for this transaction

    status public.invoice_status_enum NOT NULL DEFAULT 'draft',
    payment_method_id UUID NULLABLE REFERENCES public.payment_methods(id) ON DELETE SET NULL,
    payment_terms_id UUID NULLABLE REFERENCES public.payment_terms(id) ON DELETE SET NULL,
    paid_amount NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    -- Balance due is calculated: total_inclusive_vat - paid_amount

    partner_details JSONB NOT NULL, -- Immutable JSON snapshot of key partner details at time of invoice
    transaction_basis TEXT NULLABLE, -- e.g., "Supply of goods under contract XXX", "Services rendered for project Y"
    notes_to_partner TEXT NULLABLE,
    internal_notes TEXT NULLABLE,
    language_code TEXT NOT NULL, -- from locales.code (e.g., 'bg-BG', 'en-US') for document rendering

    is_from_subscription BOOLEAN NOT NULL DEFAULT FALSE, -- If generated from a tenant's subscription
    -- source_sales_order_id UUID NULLABLE REFERENCES public.sales_orders(id) ON DELETE SET NULL, -- If generated from a sales order

    created_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    voided_at TIMESTAMP WITH TIME ZONE NULLABLE,
    voided_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    void_reason TEXT NULLABLE,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT invoices_company_location_document_number_key UNIQUE (company_location_id, document_number),
    CONSTRAINT check_invoice_totals_consistency CHECK (ROUND(total_inclusive_vat, 5) = ROUND(total_exclusive_vat + total_vat_amount, 5)),
    CONSTRAINT check_invoice_void_details_consistency CHECK (
        (status = 'voided' AND voided_at IS NOT NULL AND voided_by_user_id IS NOT NULL AND void_reason IS NOT NULL) OR
        (status <> 'voided' AND voided_at IS NULL AND voided_by_user_id IS NULL AND void_reason IS NULL)
    ),
    CONSTRAINT check_invoice_exchange_rate_logic CHECK (
      (currency_id = (SELECT default_currency_id FROM public.companies cmp WHERE cmp.id = company_id) AND exchange_rate_to_company_default IS NULL AND total_inclusive_vat_company_default IS NULL) OR
      (currency_id <> (SELECT default_currency_id FROM public.companies cmp WHERE cmp.id = company_id) AND exchange_rate_to_company_default IS NOT NULL AND total_inclusive_vat_company_default IS NOT NULL) OR
      (exchange_rate_to_company_default IS NULL AND total_inclusive_vat_company_default IS NULL) -- Allow both null if not yet converted
    )
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_invoices_company_id ON public.invoices(company_id);
CREATE INDEX IF NOT EXISTS idx_invoices_partner_id ON public.invoices(partner_id);
CREATE INDEX IF NOT EXISTS idx_invoices_document_number ON public.invoices(company_location_id, document_number);
CREATE INDEX IF NOT EXISTS idx_invoices_issue_date ON public.invoices(issue_date);
CREATE INDEX IF NOT EXISTS idx_invoices_due_date ON public.invoices(due_date);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON public.invoices(status);
CREATE INDEX IF NOT EXISTS idx_invoices_currency_id ON public.invoices(currency_id);
-- CREATE INDEX IF NOT EXISTS idx_invoices_source_sales_order_id ON public.invoices(source_sales_order_id);
CREATE INDEX IF NOT EXISTS idx_invoices_overall_vat_treatment_summary ON public.invoices(overall_vat_treatment_summary);

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_invoices_updated_at
    BEFORE UPDATE ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.invoices IS 'Represents issued invoices to partners. Header-level information for financial billing documents.';
-- Other comments from blueprint apply


-- ### `public.invoice_items`
-- Stores individual line items for each invoice, detailing products/services, quantities, prices, and VAT treatment.
CREATE TABLE IF NOT EXISTS public.invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT, -- Denormalized

    -- Item Identification & Description (Snapshot)
    nomenclature_id UUID NULLABLE REFERENCES public.nomenclatures(id) ON DELETE SET NULL,
    item_description TEXT NOT NULL,
    item_serial_number TEXT NULLABLE, -- Specific serial if applicable & tracked
    item_batch_number TEXT NULLABLE,  -- Specific batch if applicable & tracked
    item_expiry_date DATE NULLABLE,   -- Expiry of batch/serial if applicable

    -- Quantity & Unit
    quantity NUMERIC(15, 5) NOT NULL, -- Usually positive. For returns on invoice, use credit note.
    unit_id UUID NOT NULL REFERENCES public.nomenclature_unit(id) ON DELETE RESTRICT,

    -- Pricing (Per Unit, in parent invoice's currency)
    original_unit_price_exclusive_vat NUMERIC(15, 5) NULLABLE, -- List price before any invoice-specifics
    unit_price_exclusive_vat NUMERIC(15, 5) NOT NULL,
    discount_percentage NUMERIC(5, 2) NULLABLE DEFAULT 0.00 CHECK (discount_percentage IS NULL OR (discount_percentage >= -100 AND discount_percentage <= 100)),
    discount_amount_per_unit NUMERIC(15, 5) NULLABLE DEFAULT 0.00000,

    -- Line Totals (Calculated, in parent invoice's currency)
    line_total_exclusive_vat NUMERIC(15, 5) NOT NULL,
    line_vat_amount NUMERIC(15, 5) NOT NULL,
    line_total_inclusive_vat NUMERIC(15, 5) NOT NULL,

    -- Authoritative VAT Treatment for this Line Item
    applied_vat_rule_id UUID NOT NULL REFERENCES public.vat_rules_and_exemptions(id) ON DELETE RESTRICT,
    vat_rate_percentage_snapshot NUMERIC(5, 2) NOT NULL, -- Snapshot of rate from applied_vat_rule_id at time of invoicing

    -- Bundle Information
    is_bundle_component BOOLEAN NOT NULL DEFAULT FALSE,
    bundle_parent_item_id UUID NULLABLE REFERENCES public.invoice_items(id) ON DELETE SET NULL, -- Self-ref

    -- Traceability to Source (Optional)
    source_sales_order_item_id UUID NULLABLE REFERENCES public.sales_order_items(id) ON DELETE SET NULL,
    source_subscription_id UUID NULLABLE REFERENCES public.subscriptions(id) ON DELETE SET NULL,

    item_metadata JSONB NULLABLE,
    display_order INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT check_inv_item_quantity_not_zero CHECK (quantity <> 0), -- Invoice items should have non-zero quantity
    CONSTRAINT check_inv_item_line_totals_consistency CHECK (
        ROUND(line_total_inclusive_vat, 5) = ROUND(line_total_exclusive_vat + line_vat_amount, 5)
    ),
    CONSTRAINT check_inv_item_vat_rate_snapshot CHECK (
        vat_rate_percentage_snapshot >= 0 AND vat_rate_percentage_snapshot <= 100
    ),
    CONSTRAINT check_inv_item_bundle_logic CHECK (
        (is_bundle_component = TRUE AND bundle_parent_item_id IS NOT NULL) OR
        (is_bundle_component = FALSE AND bundle_parent_item_id IS NULL)
    ),
    CONSTRAINT check_inv_item_bundle_parent_is_not_self CHECK (id <> bundle_parent_item_id OR bundle_parent_item_id IS NULL)
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice_id ON public.invoice_items(invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_company_id ON public.invoice_items(company_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_nomenclature_id ON public.invoice_items(nomenclature_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_source_sales_order_item_id ON public.invoice_items(source_sales_order_item_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_source_subscription_id ON public.invoice_items(source_subscription_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_applied_vat_rule_id ON public.invoice_items(applied_vat_rule_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_bundle_parent_item_id ON public.invoice_items(bundle_parent_item_id) WHERE is_bundle_component = TRUE;

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_invoice_items_updated_at
    BEFORE UPDATE ON public.invoice_items
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.invoice_items IS 'Stores individual line items for each invoice. All monetary values are in the currency of the parent invoice.';
-- Other comments from blueprint apply


-- ### `public.credit_notes`
-- Represents credit notes issued to partners, reducing amounts from an original invoice.
CREATE TABLE IF NOT EXISTS public.credit_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    company_location_id UUID NOT NULL REFERENCES public.company_locations(id) ON DELETE RESTRICT,
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE RESTRICT,
    referenced_invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE RESTRICT, -- The invoice being credited

    document_number TEXT NOT NULL, -- From shared sequence with invoices ('FISCAL_DOCUMENTS')
    issue_date DATE NOT NULL,
    tax_event_date DATE NOT NULL, -- Often original invoice's tax event date or date of return/agreement
    reason_code TEXT NULLABLE,     -- Structured reason (e.g., 'RETURN_GOODS', 'PRICE_ADJUSTMENT')
    reason_text TEXT NULLABLE,

    currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT, -- Should match original invoice's currency
    total_exclusive_vat NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    total_vat_amount NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    total_inclusive_vat NUMERIC(15, 5) NOT NULL DEFAULT 0.00000, -- Total credited amount (positive value)

    exchange_rate_to_company_default NUMERIC(15, 8) NULLABLE,
    total_exclusive_vat_company_default NUMERIC(15, 5) NULLABLE,
    total_vat_amount_company_default NUMERIC(15, 5) NULLABLE,
    total_inclusive_vat_company_default NUMERIC(15, 5) NULLABLE,

    vat_breakdown JSONB NULLABLE,
    overall_vat_treatment_summary public.invoice_vat_summary_enum NULLABLE,

    status public.invoice_status_enum NOT NULL DEFAULT 'draft', -- Uses invoice_status_enum, 'applied' is relevant here

    partner_details JSONB NOT NULL, -- Snapshot
    internal_notes TEXT NULLABLE,
    language_code TEXT NOT NULL, -- from locales.code

    created_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    voided_at TIMESTAMP WITH TIME ZONE NULLABLE,
    voided_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    void_reason TEXT NULLABLE,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT credit_notes_company_location_document_number_key UNIQUE (company_location_id, document_number),
    CONSTRAINT check_cn_totals_consistency CHECK (ROUND(total_inclusive_vat, 5) = ROUND(total_exclusive_vat + total_vat_amount, 5)),
    CONSTRAINT check_cn_void_details_consistency CHECK (
        (status = 'voided' AND voided_at IS NOT NULL AND voided_by_user_id IS NOT NULL AND void_reason IS NOT NULL) OR
        (status <> 'voided' AND voided_at IS NULL AND voided_by_user_id IS NULL AND void_reason IS NULL)
    ),
    CONSTRAINT check_cn_exchange_rate_logic CHECK (
      (currency_id = (SELECT default_currency_id FROM public.companies cmp WHERE cmp.id = company_id) AND exchange_rate_to_company_default IS NULL AND total_inclusive_vat_company_default IS NULL) OR
      (currency_id <> (SELECT default_currency_id FROM public.companies cmp WHERE cmp.id = company_id) AND exchange_rate_to_company_default IS NOT NULL AND total_inclusive_vat_company_default IS NOT NULL) OR
      (exchange_rate_to_company_default IS NULL AND total_inclusive_vat_company_default IS NULL)
    )
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_credit_notes_company_id ON public.credit_notes(company_id);
CREATE INDEX IF NOT EXISTS idx_credit_notes_partner_id ON public.credit_notes(partner_id);
CREATE INDEX IF NOT EXISTS idx_credit_notes_referenced_invoice_id ON public.credit_notes(referenced_invoice_id);
CREATE INDEX IF NOT EXISTS idx_credit_notes_document_number ON public.credit_notes(company_location_id, document_number);
CREATE INDEX IF NOT EXISTS idx_credit_notes_issue_date ON public.credit_notes(issue_date);
CREATE INDEX IF NOT EXISTS idx_credit_notes_status ON public.credit_notes(status);

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_credit_notes_updated_at
    BEFORE UPDATE ON public.credit_notes
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.credit_notes IS 'Represents credit notes issued to partners, reducing amounts from an original invoice. Shares document numbering with invoices.';
-- Other comments from blueprint apply


-- ### `public.credit_note_items`
-- Stores individual line items for credit notes. Values are positive; credit note context implies reduction.
CREATE TABLE IF NOT EXISTS public.credit_note_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    credit_note_id UUID NOT NULL REFERENCES public.credit_notes(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,

    referenced_invoice_item_id UUID NULLABLE REFERENCES public.invoice_items(id) ON DELETE SET NULL,

    nomenclature_id UUID NULLABLE REFERENCES public.nomenclatures(id) ON DELETE SET NULL,
    item_description TEXT NOT NULL,
    item_serial_number TEXT NULLABLE,
    item_batch_number TEXT NULLABLE,
    item_expiry_date DATE NULLABLE,

    quantity NUMERIC(15, 5) NOT NULL, -- Quantity being credited (positive value)
    unit_id UUID NOT NULL REFERENCES public.nomenclature_unit(id) ON DELETE RESTRICT,

    unit_price_exclusive_vat NUMERIC(15, 5) NOT NULL, -- Price per unit being credited

    line_total_exclusive_vat NUMERIC(15, 5) NOT NULL,
    line_vat_amount NUMERIC(15, 5) NOT NULL,
    line_total_inclusive_vat NUMERIC(15, 5) NOT NULL,

    applied_vat_rule_id UUID NOT NULL REFERENCES public.vat_rules_and_exemptions(id) ON DELETE RESTRICT,
    vat_rate_percentage_snapshot NUMERIC(5, 2) NOT NULL,

    is_bundle_component BOOLEAN NOT NULL DEFAULT FALSE,
    bundle_parent_item_id UUID NULLABLE REFERENCES public.credit_note_items(id) ON DELETE SET NULL,

    item_metadata JSONB NULLABLE,
    display_order INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT check_cn_item_quantity_positive CHECK (quantity > 0),
    CONSTRAINT check_cn_item_line_totals_consistency CHECK (
        ROUND(line_total_inclusive_vat, 5) = ROUND(line_total_exclusive_vat + line_vat_amount, 5)
    ),
    CONSTRAINT check_cn_item_vat_rate_snapshot CHECK (
        vat_rate_percentage_snapshot >= 0 AND vat_rate_percentage_snapshot <= 100
    ),
    CONSTRAINT check_cn_item_bundle_logic CHECK (
        (is_bundle_component = TRUE AND bundle_parent_item_id IS NOT NULL) OR
        (is_bundle_component = FALSE AND bundle_parent_item_id IS NULL)
    ),
    CONSTRAINT check_cn_item_bundle_parent_is_not_self CHECK (id <> bundle_parent_item_id OR bundle_parent_item_id IS NULL)
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_credit_note_items_credit_note_id ON public.credit_note_items(credit_note_id);
CREATE INDEX IF NOT EXISTS idx_credit_note_items_company_id ON public.credit_note_items(company_id);
CREATE INDEX IF NOT EXISTS idx_credit_note_items_nomenclature_id ON public.credit_note_items(nomenclature_id);
CREATE INDEX IF NOT EXISTS idx_credit_note_items_referenced_invoice_item_id ON public.credit_note_items(referenced_invoice_item_id);

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_credit_note_items_updated_at
    BEFORE UPDATE ON public.credit_note_items
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.credit_note_items IS 'Stores individual line items for credit notes. Values are typically positive; the credit note context implies reduction.';
-- Other comments from blueprint apply


-- ### `public.debit_notes`
-- Represents debit notes issued to partners, increasing amounts owed, typically related to an original invoice.
CREATE TABLE IF NOT EXISTS public.debit_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    company_location_id UUID NOT NULL REFERENCES public.company_locations(id) ON DELETE RESTRICT,
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE RESTRICT,
    referenced_invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE RESTRICT, -- Invoice being debited/added to

    document_number TEXT NOT NULL, -- From shared sequence ('FISCAL_DOCUMENTS')
    issue_date DATE NOT NULL,
    tax_event_date DATE NOT NULL,
    reason_code TEXT NULLABLE,     -- e.g., 'ADDITIONAL_SHIPPING', 'PRICE_CORRECTION_UP'
    reason_text TEXT NULLABLE,

    currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT,
    total_exclusive_vat NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    total_vat_amount NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    total_inclusive_vat NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,

    exchange_rate_to_company_default NUMERIC(15, 8) NULLABLE,
    total_exclusive_vat_company_default NUMERIC(15, 5) NULLABLE,
    total_vat_amount_company_default NUMERIC(15, 5) NULLABLE,
    total_inclusive_vat_company_default NUMERIC(15, 5) NULLABLE,

    vat_breakdown JSONB NULLABLE,
    overall_vat_treatment_summary public.invoice_vat_summary_enum NULLABLE,

    status public.invoice_status_enum NOT NULL DEFAULT 'draft', -- Uses invoice_status_enum
    payment_method_id UUID NULLABLE REFERENCES public.payment_methods(id) ON DELETE SET NULL,
    payment_terms_id UUID NULLABLE REFERENCES public.payment_terms(id) ON DELETE SET NULL,
    paid_amount NUMERIC(15, 5) NOT NULL DEFAULT 0.00000, -- Tracks payments for this debit note

    partner_details JSONB NOT NULL, -- Snapshot
    internal_notes TEXT NULLABLE,
    language_code TEXT NOT NULL, -- from locales.code

    created_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    voided_at TIMESTAMP WITH TIME ZONE NULLABLE,
    voided_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    void_reason TEXT NULLABLE,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT debit_notes_company_location_document_number_key UNIQUE (company_location_id, document_number),
    CONSTRAINT check_dn_totals_consistency CHECK (ROUND(total_inclusive_vat, 5) = ROUND(total_exclusive_vat + total_vat_amount, 5)),
    CONSTRAINT check_dn_void_details_consistency CHECK (
        (status = 'voided' AND voided_at IS NOT NULL AND voided_by_user_id IS NOT NULL AND void_reason IS NOT NULL) OR
        (status <> 'voided' AND voided_at IS NULL AND voided_by_user_id IS NULL AND void_reason IS NULL)
    ),
    CONSTRAINT check_dn_exchange_rate_logic CHECK (
      (currency_id = (SELECT default_currency_id FROM public.companies cmp WHERE cmp.id = company_id) AND exchange_rate_to_company_default IS NULL AND total_inclusive_vat_company_default IS NULL) OR
      (currency_id <> (SELECT default_currency_id FROM public.companies cmp WHERE cmp.id = company_id) AND exchange_rate_to_company_default IS NOT NULL AND total_inclusive_vat_company_default IS NOT NULL) OR
      (exchange_rate_to_company_default IS NULL AND total_inclusive_vat_company_default IS NULL)
    )
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_debit_notes_company_id ON public.debit_notes(company_id);
CREATE INDEX IF NOT EXISTS idx_debit_notes_partner_id ON public.debit_notes(partner_id);
CREATE INDEX IF NOT EXISTS idx_debit_notes_referenced_invoice_id ON public.debit_notes(referenced_invoice_id);
CREATE INDEX IF NOT EXISTS idx_debit_notes_document_number ON public.debit_notes(company_location_id, document_number);
CREATE INDEX IF NOT EXISTS idx_debit_notes_issue_date ON public.debit_notes(issue_date);
CREATE INDEX IF NOT EXISTS idx_debit_notes_status ON public.debit_notes(status);

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_debit_notes_updated_at
    BEFORE UPDATE ON public.debit_notes
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.debit_notes IS 'Represents debit notes issued to partners, increasing amounts owed, typically related to an original invoice. Shares document numbering with invoices.';
-- Other comments from blueprint apply


-- ### `public.debit_note_items`
-- Stores individual line items for debit notes, detailing additional charges.
CREATE TABLE IF NOT EXISTS public.debit_note_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    debit_note_id UUID NOT NULL REFERENCES public.debit_notes(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,

    nomenclature_id UUID NULLABLE REFERENCES public.nomenclatures(id) ON DELETE SET NULL,
    item_description TEXT NOT NULL,

    quantity NUMERIC(15, 5) NOT NULL DEFAULT 1,
    unit_id UUID NOT NULL REFERENCES public.nomenclature_unit(id) ON DELETE RESTRICT,

    unit_price_exclusive_vat NUMERIC(15, 5) NOT NULL,

    line_total_exclusive_vat NUMERIC(15, 5) NOT NULL,
    line_vat_amount NUMERIC(15, 5) NOT NULL,
    line_total_inclusive_vat NUMERIC(15, 5) NOT NULL,

    applied_vat_rule_id UUID NOT NULL REFERENCES public.vat_rules_and_exemptions(id) ON DELETE RESTRICT,
    vat_rate_percentage_snapshot NUMERIC(5, 2) NOT NULL,

    is_bundle_component BOOLEAN NOT NULL DEFAULT FALSE,
    bundle_parent_item_id UUID NULLABLE REFERENCES public.debit_note_items(id) ON DELETE SET NULL,

    item_metadata JSONB NULLABLE,
    display_order INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT check_dn_item_quantity_positive CHECK (quantity > 0),
    CONSTRAINT check_dn_item_line_totals_consistency CHECK (
        ROUND(line_total_inclusive_vat, 5) = ROUND(line_total_exclusive_vat + line_vat_amount, 5)
    ),
    CONSTRAINT check_dn_item_vat_rate_snapshot CHECK (
        vat_rate_percentage_snapshot >= 0 AND vat_rate_percentage_snapshot <= 100
    ),
    CONSTRAINT check_dn_item_bundle_logic CHECK (
        (is_bundle_component = TRUE AND bundle_parent_item_id IS NOT NULL) OR
        (is_bundle_component = FALSE AND bundle_parent_item_id IS NULL)
    ),
    CONSTRAINT check_dn_item_bundle_parent_is_not_self CHECK (id <> bundle_parent_item_id OR bundle_parent_item_id IS NULL)
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_debit_note_items_debit_note_id ON public.debit_note_items(debit_note_id);
CREATE INDEX IF NOT EXISTS idx_debit_note_items_company_id ON public.debit_note_items(company_id);
CREATE INDEX IF NOT EXISTS idx_debit_note_items_nomenclature_id ON public.debit_note_items(nomenclature_id);

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_debit_note_items_updated_at
    BEFORE UPDATE ON public.debit_note_items
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.debit_note_items IS 'Stores individual line items for debit notes, detailing additional charges.';
-- Other comments from blueprint apply


-- #############################################################################
-- # G. Fiscalization Module
-- #############################################################################
-- Entities for managing fiscal receipts from POS or cash/card invoice payments.

-- ## G.1. ENUM Types for Fiscalization

-- ### `public.fiscal_receipt_status_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'fiscal_receipt_status_enum') THEN
        CREATE TYPE public.fiscal_receipt_status_enum AS ENUM (
            'issued',       -- Successfully issued and recorded
            'void_pending', -- Request to void has been sent to fiscal device, awaiting confirmation
            'voided',       -- Successfully voided by the fiscal device
            'error'         -- An error occurred during issuance or voiding with the fiscal device
        );
        COMMENT ON TYPE public.fiscal_receipt_status_enum IS 'Defines the status of a fiscal receipt interaction with a fiscal device.';
    END IF;
END$$;


-- ## G.2. Core Tables for Fiscalization

-- ### `public.fiscal_receipts`
-- Stores information about fiscal receipts generated by fiscal devices.
CREATE TABLE IF NOT EXISTS public.fiscal_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    company_location_id UUID NOT NULL REFERENCES public.company_locations(id) ON DELETE RESTRICT, -- Location of the fiscal device

    -- Source Document (The transaction being fiscalized)
    source_sales_order_id UUID NULLABLE REFERENCES public.sales_orders(id) ON DELETE SET NULL, -- For POS sales fiscalization
    source_invoice_id UUID NULLABLE REFERENCES public.invoices(id) ON DELETE SET NULL,       -- For fiscalizing payment of a standard invoice

    -- Fiscal Device Response Data
    unique_sale_number TEXT NOT NULL,       -- USN / УНП from fiscal device (Unique Sale Number)
    fiscal_receipt_number TEXT NOT NULL,    -- Sequential receipt number from fiscal device (Номер на ФБ)
    fiscal_device_serial_number TEXT NOT NULL, -- Serial number of the fiscal device (ИН на ФУ)
    receipt_datetime TIMESTAMP WITH TIME ZONE NOT NULL, -- Date and time of fiscal transaction from device

    -- Transaction Details (Must be in Company Default Currency, e.g., BGN for Bulgaria)
    total_amount NUMERIC(15, 5) NOT NULL, -- Total amount on the fiscal receipt
    currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT, -- Must be company's default currency
    payment_method_id UUID NOT NULL REFERENCES public.payment_methods(id) ON DELETE RESTRICT, -- (e.g., cash, card)

    -- Operator & QR Code
    operator_id TEXT NULLABLE,              -- Operator ID from company_user_operators, if applicable and sent to device
    fiscal_qr_code_data TEXT NULLABLE,      -- Data content of the fiscal QR code, if generated/returned by device

    -- Status & Voiding
    status public.fiscal_receipt_status_enum NOT NULL DEFAULT 'issued',
    is_void BOOLEAN NOT NULL DEFAULT FALSE, -- True if this receipt IS a voiding document (storno receipt)
    voids_fiscal_receipt_id UUID NULLABLE REFERENCES public.fiscal_receipts(id) ON DELETE SET NULL, -- If is_void=true, this points to the original receipt (USN) being voided
    voided_by_fiscal_receipt_id UUID NULLABLE REFERENCES public.fiscal_receipts(id) ON DELETE SET NULL, -- If this receipt was voided, this points to the storno fiscal_receipts record

    -- Additional Data
    raw_fiscal_response JSONB NULLABLE,     -- Optional: Complete raw response from fiscal device API

    -- Audit
    created_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT fiscal_receipt_source_document_check CHECK (
        num_nonnulls(source_sales_order_id, source_invoice_id) <= 1 -- Can be 0 if fiscal receipt is ad-hoc/not directly linked to SO/Invoice initially
    ),
    CONSTRAINT fiscal_receipt_voiding_logic_check CHECK (
        (is_void = TRUE AND voids_fiscal_receipt_id IS NOT NULL AND voided_by_fiscal_receipt_id IS NULL) OR -- This IS a voiding receipt
        (is_void = FALSE AND voids_fiscal_receipt_id IS NULL) -- This is NOT a voiding receipt (it could BE voided by another)
    ),
    CONSTRAINT fiscal_receipt_currency_is_company_default_placeholder CHECK (
        -- This requires a function or complex logic to verify currency_id against company's default.
        -- To be enforced by application logic or a DB function.
        TRUE -- Placeholder from blueprint; actual enforcement in application.
    ),
    CONSTRAINT fiscal_receipt_unique_company_usn UNIQUE (company_id, unique_sale_number) -- USN should be unique per company
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_company_id ON public.fiscal_receipts(company_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_company_location_id ON public.fiscal_receipts(company_location_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_source_sales_order_id ON public.fiscal_receipts(source_sales_order_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_source_invoice_id ON public.fiscal_receipts(source_invoice_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_unique_sale_number ON public.fiscal_receipts(company_id, unique_sale_number); -- Covered by UNIQUE constraint
CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_fiscal_receipt_number_device ON public.fiscal_receipts(fiscal_device_serial_number, fiscal_receipt_number); -- Common lookup
CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_receipt_datetime ON public.fiscal_receipts(receipt_datetime);
CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_status ON public.fiscal_receipts(status);
CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_voids_fiscal_receipt_id ON public.fiscal_receipts(voids_fiscal_receipt_id) WHERE is_void = TRUE;
CREATE INDEX IF NOT EXISTS idx_fiscal_receipts_voided_by_fiscal_receipt_id ON public.fiscal_receipts(voided_by_fiscal_receipt_id) WHERE voided_by_fiscal_receipt_id IS NOT NULL;

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_fiscal_receipts_updated_at
    BEFORE UPDATE ON public.fiscal_receipts
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.fiscal_receipts IS 'Stores information about fiscal receipts generated by fiscal devices, including key fiscalization data and links to source documents.';
COMMENT ON COLUMN public.fiscal_receipts.company_location_id IS 'The company location where the fiscal device is registered and the transaction occurred.';
COMMENT ON COLUMN public.fiscal_receipts.source_sales_order_id IS 'Link to the sales order that this fiscal receipt corresponds to (e.g., for POS sales).';
COMMENT ON COLUMN public.fiscal_receipts.source_invoice_id IS 'Link to the invoice that this fiscal receipt corresponds to (e.g., for cash/card payment of a standard invoice).';
COMMENT ON COLUMN public.fiscal_receipts.unique_sale_number IS 'Unique Sale Number (USN / УНП) returned by the fiscal device for the transaction. Should be unique per company.';
COMMENT ON COLUMN public.fiscal_receipts.fiscal_receipt_number IS 'Sequential receipt number printed on the fiscal slip, as returned by the fiscal device.';
COMMENT ON COLUMN public.fiscal_receipts.fiscal_device_serial_number IS 'Serial number of the fiscal device (ФП № / ИН на ФУ) that generated this receipt.';
COMMENT ON COLUMN public.fiscal_receipts.receipt_datetime IS 'Exact date and time of the fiscal transaction as recorded by the fiscal device.';
COMMENT ON COLUMN public.fiscal_receipts.total_amount IS 'Total amount of the fiscal receipt, must be in the company''s default currency (e.g., BGN).';
COMMENT ON COLUMN public.fiscal_receipts.currency_id IS 'Currency of the fiscal receipt; MUST be the company''s default currency.';
COMMENT ON COLUMN public.fiscal_receipts.operator_id IS 'Operator ID (from company_user_operators) of the user who performed the fiscal transaction, if applicable.';
COMMENT ON COLUMN public.fiscal_receipts.fiscal_qr_code_data IS 'Data content of the fiscal QR code, if available from the fiscal device response.';
COMMENT ON COLUMN public.fiscal_receipts.status IS 'Current status of the fiscal receipt (e.g., issued, voided, error).';
COMMENT ON COLUMN public.fiscal_receipts.is_void IS 'True if this fiscal receipt record itself represents the act of voiding a previous fiscal receipt (i.e., it is a storno receipt).';
COMMENT ON COLUMN public.fiscal_receipts.voids_fiscal_receipt_id IS 'If is_void is true, this references the original fiscal_receipts.id that this document is voiding.';
COMMENT ON COLUMN public.fiscal_receipts.voided_by_fiscal_receipt_id IS 'If this fiscal receipt was voided by another fiscal receipt, this references the fiscal_receipts.id of the voiding document.';
COMMENT ON COLUMN public.fiscal_receipts.raw_fiscal_response IS 'Optional JSONB field to store the complete raw response from the fiscal device API for audit or debugging.';


-- ### `public.fiscal_receipt_items`
-- Stores a snapshot of individual line items as processed and fiscalized by the fiscal device.
CREATE TABLE IF NOT EXISTS public.fiscal_receipt_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fiscal_receipt_id UUID NOT NULL REFERENCES public.fiscal_receipts(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT, -- Denormalized for RLS/query convenience

    -- Source Item Traceability (Optional but Recommended)
    source_sales_order_item_id UUID NULLABLE REFERENCES public.sales_order_items(id) ON DELETE SET NULL,
    source_invoice_item_id UUID NULLABLE REFERENCES public.invoice_items(id) ON DELETE SET NULL,

    -- Item Details as Sent To/Processed By Fiscal Device (Must be in Company Default Currency)
    item_description TEXT NOT NULL,         -- Description of the item/service as sent to fiscal device
    nomenclature_code_fiscal TEXT NULLABLE, -- Specific code for the item used by the fiscal system/NRA classification, if different from internal

    quantity NUMERIC(15, 5) NOT NULL,
    unit_price_inclusive_vat NUMERIC(15, 5) NOT NULL, -- Fiscal devices often work with final price per unit
    line_total_inclusive_vat NUMERIC(15, 5) NOT NULL, -- quantity * unit_price_inclusive_vat

    -- VAT Details as Processed By Fiscal Device
    vat_group_code_fiscal TEXT NOT NULL, -- VAT group/rate identifier used by fiscal device (e.g., 'А', 'Б', 'В', 'Г' in BG)
    vat_rate_percentage_fiscal NUMERIC(5, 2) NOT NULL, -- The VAT rate applied by the fiscal device for this line
    line_vat_amount_fiscal NUMERIC(15, 5) NOT NULL,   -- VAT amount for this line as calculated by fiscal device
    line_total_exclusive_vat_fiscal NUMERIC(15,5) NOT NULL, -- Derived: line_total_inclusive_vat - line_vat_amount_fiscal

    -- Display Order
    display_order INTEGER NOT NULL DEFAULT 0,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT check_fiscal_item_source_document_item CHECK (
        num_nonnulls(source_sales_order_item_id, source_invoice_item_id) <= 1 -- Can be 0 if items are manually entered for fiscal receipt
    ),
    CONSTRAINT check_fiscal_item_line_totals_consistency CHECK (
       ROUND(line_total_inclusive_vat, 5) = ROUND(line_total_exclusive_vat_fiscal + line_vat_amount_fiscal, 5)
    ),
    CONSTRAINT check_fiscal_item_derived_exclusive_total CHECK (
        ROUND(line_total_exclusive_vat_fiscal, 5) = ROUND(line_total_inclusive_vat - line_vat_amount_fiscal, 5)
    )
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_fiscal_receipt_items_fiscal_receipt_id ON public.fiscal_receipt_items(fiscal_receipt_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_receipt_items_company_id ON public.fiscal_receipt_items(company_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_receipt_items_source_sales_order_item_id ON public.fiscal_receipt_items(source_sales_order_item_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_receipt_items_source_invoice_item_id ON public.fiscal_receipt_items(source_invoice_item_id);

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_fiscal_receipt_items_updated_at
    BEFORE UPDATE ON public.fiscal_receipt_items
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.fiscal_receipt_items IS 'Stores a snapshot of individual line items as processed and fiscalized by the fiscal device. All monetary values MUST be in the company''s default currency.';
COMMENT ON COLUMN public.fiscal_receipt_items.fiscal_receipt_id IS 'Link to the parent fiscal receipt header.';
COMMENT ON COLUMN public.fiscal_receipt_items.company_id IS 'Denormalized company_id, should match parent fiscal_receipt''s company_id.';
COMMENT ON COLUMN public.fiscal_receipt_items.source_sales_order_item_id IS 'Optional link to the originating sales_order_item, if applicable.';
COMMENT ON COLUMN public.fiscal_receipt_items.source_invoice_item_id IS 'Optional link to the originating invoice_item, if applicable (e.g., invoice paid by cash).';
COMMENT ON COLUMN public.fiscal_receipt_items.item_description IS 'Description of the item/service exactly as sent to or processed by the fiscal device.';
COMMENT ON COLUMN public.fiscal_receipt_items.nomenclature_code_fiscal IS 'Specific item code used for fiscal reporting/device, if different from internal nomenclature codes.';
COMMENT ON COLUMN public.fiscal_receipt_items.quantity IS 'Quantity of the item/service as processed by the fiscal device.';
COMMENT ON COLUMN public.fiscal_receipt_items.unit_price_inclusive_vat IS 'Unit price including VAT, as processed by the fiscal device (in company default currency).';
COMMENT ON COLUMN public.fiscal_receipt_items.line_total_inclusive_vat IS 'Total amount for this line including VAT, as processed by the fiscal device (in company default currency).';
COMMENT ON COLUMN public.fiscal_receipt_items.vat_group_code_fiscal IS 'VAT group identifier (e.g., "А", "Б") used by the fiscal device for this line item.';
COMMENT ON COLUMN public.fiscal_receipt_items.vat_rate_percentage_fiscal IS 'The VAT rate percentage applied by the fiscal device for this line.';
COMMENT ON COLUMN public.fiscal_receipt_items.line_vat_amount_fiscal IS 'The VAT amount for this line as calculated/confirmed by the fiscal device.';
COMMENT ON COLUMN public.fiscal_receipt_items.line_total_exclusive_vat_fiscal IS 'The taxable base for this line as determined by the fiscal device (total incl. VAT - VAT amount).';
COMMENT ON COLUMN public.fiscal_receipt_items.display_order IS 'Order of the item as it appeared on the fiscal slip.';


-- #############################################################################
-- # H. Procurement & Purchasing Module
-- #############################################################################
-- Entities for managing purchase orders issued to suppliers.

-- ## H.1. ENUM Types for Procurement

-- ### `public.purchase_order_status_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'purchase_order_status_enum') THEN
        CREATE TYPE public.purchase_order_status_enum AS ENUM (
            'draft',                        -- PO created, not yet finalized or sent to supplier
            'pending_approval',             -- Submitted for internal approval (if workflow exists)
            'awaiting_supplier_confirmation', -- Sent to supplier, awaiting their acknowledgement/confirmation
            'confirmed_by_supplier',        -- Confirmed by supplier, goods/services expected
            'partially_received',           -- Some items/quantities have been received via Goods Receipt Notes
            'fully_received',               -- All items/quantities have been received
            'closed',                       -- PO fulfilled, all related invoices/payments processed (final state)
            'cancelled'                     -- PO cancelled before fulfillment
        );
        COMMENT ON TYPE public.purchase_order_status_enum IS 'Defines the lifecycle states of a purchase order.';
    END IF;
END$$;


-- ## H.2. Core Tables for Procurement

-- ### `public.purchase_orders`
-- Represents formal purchase orders issued to suppliers for goods or services.
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    company_location_id UUID NOT NULL REFERENCES public.company_locations(id) ON DELETE RESTRICT, -- Location placing the order or primary receiving location
    supplier_partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE RESTRICT, -- The partner acting as the supplier

    -- Supplier Details Snapshot (for integrity of PO-time supplier info)
    supplier_details JSONB NOT NULL,
        -- Snapshot: {"name": "Supplier Corp Ltd", "contact_person": "Jane Smith", "email": "jane@supplier.com", "vat_id": "...", "address": "..."}

    -- PO Identification & Dates
    po_number TEXT NOT NULL,            -- Generated using document_sequence_definitions (type 'PURCHASE_ORDERS')
    order_date DATE NOT NULL DEFAULT CURRENT_DATE, -- Date the PO was created/placed
    expected_delivery_date DATE NULLABLE, -- Overall expected delivery date from supplier for the whole order
    actual_delivery_date DATE NULLABLE,   -- Actual final delivery date if tracked at header level (more common per GRN or item)

    -- References
    supplier_reference_number TEXT NULLABLE, -- Supplier's reference for this order (e.g., their quote number)
    internal_buyer_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL, -- User (employee of tenant) responsible for this purchase

    -- Addresses
    ship_to_company_location_id UUID NULLABLE REFERENCES public.company_locations(id) ON DELETE RESTRICT, -- Specific tenant's location goods should be delivered to
    ship_to_address_details JSONB NULLABLE,  -- Snapshot of delivery address if more specific than company_location's main address

    -- Currency & Estimated Totals (Derived from purchase_order_items)
    currency_id UUID NOT NULL REFERENCES public.currencies(id) ON DELETE RESTRICT,
    estimated_total_exclusive_vat NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    estimated_total_vat_amount NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,    -- VAT the supplier might charge (depends on supplier's location, our status)
    estimated_total_inclusive_vat NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,

    -- Status & Control
    status public.purchase_order_status_enum NOT NULL DEFAULT 'draft',
    payment_terms_id UUID NULLABLE REFERENCES public.payment_terms(id) ON DELETE SET NULL, -- Payment terms agreed with supplier (FK to table in Invoicing module)

    -- Notes
    notes_to_supplier TEXT NULLABLE,
    internal_notes TEXT NULLABLE,

    -- Audit
    created_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    cancelled_at TIMESTAMP WITH TIME ZONE NULLABLE,
    cancellation_reason TEXT NULLABLE,
    cancellation_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT purchase_orders_company_location_po_number_key UNIQUE (company_location_id, po_number),
    CONSTRAINT check_po_cancellation_details CHECK (
        (status = 'cancelled' AND cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND cancellation_user_id IS NOT NULL) OR
        (status <> 'cancelled' AND cancelled_at IS NULL AND cancellation_reason IS NULL AND cancellation_user_id IS NULL)
    ),
    CONSTRAINT check_po_estimated_totals CHECK (
        ROUND(estimated_total_inclusive_vat, 5) = ROUND(estimated_total_exclusive_vat + estimated_total_vat_amount, 5)
    )
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_partner_id ON public.purchase_orders(supplier_partner_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_po_number ON public.purchase_orders(company_location_id, po_number);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_order_date ON public.purchase_orders(order_date);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON public.purchase_orders(status);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_internal_buyer_id ON public.purchase_orders(internal_buyer_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_ship_to_company_location_id ON public.purchase_orders(ship_to_company_location_id);


-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_purchase_orders_updated_at
    BEFORE UPDATE ON public.purchase_orders
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.purchase_orders IS 'Represents formal purchase orders issued to suppliers for goods or services by a tenant company.';
COMMENT ON COLUMN public.purchase_orders.company_location_id IS 'The company location primarily responsible for placing this PO or intended for initial receipt.';
COMMENT ON COLUMN public.purchase_orders.supplier_partner_id IS 'Reference to the partner record designated as the supplier.';
COMMENT ON COLUMN public.purchase_orders.supplier_details IS 'Immutable JSON snapshot of key supplier details (name, contacts, address, identifiers) at the time of PO placement.';
COMMENT ON COLUMN public.purchase_orders.po_number IS 'Unique purchase order number, generated per company_location_id via document_sequence_definitions.';
COMMENT ON COLUMN public.purchase_orders.internal_buyer_id IS 'User (buyer/procurement staff within the tenant company) primarily associated with this purchase order.';
COMMENT ON COLUMN public.purchase_orders.ship_to_company_location_id IS 'Specific company location where goods are to be delivered. Can be different from company_location_id placing the order.';
COMMENT ON COLUMN public.purchase_orders.ship_to_address_details IS 'Snapshot of the specific delivery address if it differs from the main address of ship_to_company_location_id.';
COMMENT ON COLUMN public.purchase_orders.currency_id IS 'Currency for all monetary values in this purchase order and its items.';
COMMENT ON COLUMN public.purchase_orders.estimated_total_exclusive_vat IS 'Estimated total PO value, excluding VAT, in the PO currency. Derived from PO items.';
COMMENT ON COLUMN public.purchase_orders.estimated_total_vat_amount IS 'Estimated VAT amount the supplier might charge (subject to their invoicing rules and location).';
COMMENT ON COLUMN public.purchase_orders.status IS 'Current lifecycle status of the purchase order.';
COMMENT ON COLUMN public.purchase_orders.payment_terms_id IS 'Payment terms agreed with the supplier for this PO.';
COMMENT ON COLUMN public.purchase_orders.cancellation_user_id IS 'User who performed the cancellation of the purchase order.';


-- ### `public.purchase_order_items`
-- Stores individual line items for purchase orders, detailing products/services to be procured from suppliers.
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT, -- Denormalized

    -- Item Identification & Description
    nomenclature_id UUID NOT NULL REFERENCES public.nomenclatures(id) ON DELETE RESTRICT, -- What is being ordered
    item_description TEXT NOT NULL,         -- Can be from nomenclature or customized for PO
    supplier_item_code TEXT NULLABLE,       -- Supplier's own code/SKU for this item

    -- Quantity & Unit
    quantity_ordered NUMERIC(15, 5) NOT NULL,
    unit_id UUID NOT NULL REFERENCES public.nomenclature_unit(id) ON DELETE RESTRICT,

    -- Costing (Per Unit, in PO currency)
    unit_cost_exclusive_vat NUMERIC(15, 5) NOT NULL, -- Agreed cost per unit from supplier, excluding their VAT
    -- Discounts from supplier could be modeled with discount_percentage/amount fields if needed,
    -- or reflected in a net unit_cost_exclusive_vat. For now, assume net cost.

    -- Line Totals (Calculated, in PO currency)
    line_total_exclusive_vat NUMERIC(15, 5) NOT NULL,
    estimated_line_vat_amount NUMERIC(15, 5) NOT NULL DEFAULT 0.00000, -- Estimated VAT supplier will charge on this line
    line_total_inclusive_vat NUMERIC(15, 5) NOT NULL,  -- Provisional total for this line including estimated supplier VAT

    -- Estimated VAT Treatment (Supplier's VAT to us)
    estimated_supplier_vat_rule_id UUID NULLABLE REFERENCES public.vat_rules_and_exemptions(id) ON DELETE SET NULL, -- Rule supplier might apply
    estimated_supplier_vat_rate_percentage NUMERIC(5, 2) NULLABLE,

    -- Tracking Received Quantities (Updated by Goods Receipt Note process)
    quantity_received NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
    -- quantity_pending_receipt can be calculated: quantity_ordered - quantity_received

    -- Delivery Information (Per-line specifics)
    requested_delivery_date DATE NULLABLE, -- If different from PO header for this line
    confirmed_delivery_date DATE NULLABLE, -- Supplier confirmed delivery date for this line

    -- Additional Dynamic Data
    item_metadata JSONB NULLABLE,

    -- Display & Ordering
    display_order INTEGER NOT NULL DEFAULT 0,

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT check_po_item_quantity_ordered_positive CHECK (quantity_ordered > 0),
    CONSTRAINT check_po_item_received_quantity CHECK (quantity_received >= 0 AND quantity_received <= quantity_ordered),
    CONSTRAINT check_po_item_line_totals_consistency CHECK (
        ROUND(line_total_inclusive_vat, 5) = ROUND(line_total_exclusive_vat + estimated_line_vat_amount, 5)
    )
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_purchase_order_items_purchase_order_id ON public.purchase_order_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_items_company_id ON public.purchase_order_items(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_items_nomenclature_id ON public.purchase_order_items(nomenclature_id);

-- Update Trigger
CREATE OR REPLACE TRIGGER set_public_purchase_order_items_updated_at
    BEFORE UPDATE ON public.purchase_order_items
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.purchase_order_items IS 'Stores individual line items for purchase orders, detailing products/services to be procured from suppliers by a tenant company.';
COMMENT ON COLUMN public.purchase_order_items.purchase_order_id IS 'Link to the parent purchase order header.';
COMMENT ON COLUMN public.purchase_order_items.nomenclature_id IS 'The catalog item being ordered by the tenant company.';
COMMENT ON COLUMN public.purchase_order_items.item_description IS 'Description of the item/service as it appears on the PO. Can be from nomenclature or customized.';
COMMENT ON COLUMN public.purchase_order_items.supplier_item_code IS 'The supplier''s specific code or part number for the ordered item.';
COMMENT ON COLUMN public.purchase_order_items.quantity_ordered IS 'Quantity of the item/service being ordered from the supplier.';
COMMENT ON COLUMN public.purchase_order_items.unit_cost_exclusive_vat IS 'Agreed cost per unit from the supplier, excluding any VAT they might charge to the tenant.';
COMMENT ON COLUMN public.purchase_order_items.estimated_line_vat_amount IS 'Estimated VAT amount the supplier will charge the tenant for this line item.';
COMMENT ON COLUMN public.purchase_order_items.estimated_supplier_vat_rule_id IS 'The VAT rule expected to be applied by the supplier for this item. FK to vat_rules_and_exemptions.';
COMMENT ON COLUMN public.purchase_order_items.quantity_received IS 'Quantity of this item that has been received against this PO line via Goods Receipt Notes.';
COMMENT ON COLUMN public.purchase_order_items.item_metadata IS 'JSONB field for storing any other relevant details or specifications for this PO line item (e.g., specific grade, color).';


-- #############################################################################
-- # I. Inventory Management Module
-- #############################################################################
-- Entities for managing storages, goods receipts, actual stock items,
-- allocations, and stock movement logging.

-- ## I.1. ENUM Types for Inventory Management

-- ### `public.storage_status_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'storage_status_enum') THEN
        CREATE TYPE public.storage_status_enum AS ENUM (
            'active',       -- Fully operational and available
            'inactive',     -- Temporarily unavailable (e.g., under audit, maintenance)
            'removed'       -- Permanently decommissioned (record preserved for history/audit)
        );
        COMMENT ON TYPE public.storage_status_enum IS 'Defines the operational status of an inventory storage location.';
    END IF;
END$$;

-- ### `public.storage_type_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'storage_type_enum') THEN
        CREATE TYPE public.storage_type_enum AS ENUM (
            'general',      -- Standard storage for regular inventory
            'scrap',        -- Storage for damaged, defective, or scrap items
            'quarantine',   -- Temporary storage for items awaiting inspection/decision
            'transit',      -- Logical storage for items currently in transfer between locations/storages
            'returns'       -- Storage specifically for returned goods awaiting processing
        );
        COMMENT ON TYPE public.storage_type_enum IS 'Categorizes the purpose or type of an inventory storage location.';
    END IF;
END$$;

-- ### `public.grn_status_enum` (Goods Receipt Note Status)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'grn_status_enum') THEN
        CREATE TYPE public.grn_status_enum AS ENUM (
            'draft',                -- GRN created, not yet finalized
            'pending_inspection',   -- Goods received, awaiting quality/quantity inspection
            'partially_completed',  -- Some items processed and moved to stock, others pending/rejected
            'completed',            -- All items processed and moved to stock successfully
            'cancelled'             -- GRN cancelled before processing items into stock
        );
        COMMENT ON TYPE public.grn_status_enum IS 'Defines the lifecycle states of a Goods Receipt Note.';
    END IF;
END$$;

-- ### `public.inventory_stock_item_status_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inventory_stock_item_status_enum') THEN
        CREATE TYPE public.inventory_stock_item_status_enum AS ENUM (
            'available',            -- In stock and available for allocation/sale/use
            'allocated',            -- Reserved for a specific demand (e.g., sales order, production order)
            'quarantined',          -- Held for inspection or quality control, not available
            'damaged',              -- Damaged stock, not available for sale
            'expired',              -- Stock has passed its expiry date
            'sold_pending_dispatch',-- Sold (e.g. invoiced) and awaiting physical dispatch from warehouse
            'dispatched',           -- Physically left the warehouse (e.g., shipped to customer) / Consumed
            'returned_to_supplier', -- Stock returned to the supplier
            'in_transfer_outgoing', -- Stock is currently being transferred to another internal location (source side)
            'in_transfer_incoming', -- Stock is expected from another internal location (destination side - conceptual, usually managed by transfer doc)
            'consumed_in_production',-- Used as a component in a manufacturing process
            'written_off'           -- Stock value written off for other reasons (e.g., obsolescence, loss)
        );
        COMMENT ON TYPE public.inventory_stock_item_status_enum IS 'Defines the various statuses of an inventory stock item, reflecting its availability and lifecycle stage.';
    END IF;
END$$;

-- ### `public.stock_allocation_status_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'stock_allocation_status_enum') THEN
        CREATE TYPE public.stock_allocation_status_enum AS ENUM (
            'active_allocation',    -- Stock is currently allocated/reserved for the demand
            'partially_fulfilled',  -- Part of this specific allocation has been dispatched/consumed from this allocation record
            'fully_fulfilled',      -- Entirety of this specific allocation has been dispatched/consumed
            'cancelled'             -- Allocation was cancelled (e.g., order item cancelled, stock reallocated)
        );
        COMMENT ON TYPE public.stock_allocation_status_enum IS 'Defines the status of a specific stock allocation line, linking demand to supply.';
    END IF;
END$$;

-- ### `public.stock_movement_type_enum`
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'stock_movement_type_enum') THEN
        CREATE TYPE public.stock_movement_type_enum AS ENUM (
            -- Positive Stock Movements (Increase on-hand quantity)
            'goods_receipt_from_supplier',
            'sales_return_receipt',
            'production_output_receipt',
            'stock_adjustment_increase',
            'internal_transfer_in',
            -- Negative Stock Movements (Decrease on-hand quantity or change status)
            'sales_dispatch',
            'purchase_return_to_supplier',
            'production_component_consumption',
            'stock_adjustment_decrease',
            'internal_transfer_out',
            'stock_write_off',
            -- Status Change Only (No quantity change, but affects availability/state)
            'status_change_to_allocated',
            'status_change_to_available',
            'status_change_to_quarantined',
            'status_change_to_damaged',
            'status_change_to_expired'
        );
        COMMENT ON TYPE public.stock_movement_type_enum IS 'Defines the nature of a stock movement or status change event in the stock audit log.';
    END IF;
END$$;


-- ## I.2. Storage Management Tables

-- ### `public.storages`
-- Manages different inventory storage locations (warehouses, bins, shelves) for a company.
CREATE TABLE IF NOT EXISTS public.storages (
    id UUID PRIMARY KEY DEFAULT public.gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies (id) ON DELETE RESTRICT,
    company_location_id UUID NOT NULL REFERENCES public.company_locations (id) ON DELETE RESTRICT, -- Physical company location this storage is part of
    name TEXT NOT NULL,                                                     -- Human-readable name (e.g., "Main Warehouse", "Showroom Stock", "Bin A-01")
    description TEXT,
    parent_id UUID REFERENCES public.storages (id) ON DELETE SET NULL,      -- For hierarchical storage (e.g., bins within shelves)
    type public.storage_type_enum NOT NULL DEFAULT 'general',
    status public.storage_status_enum NOT NULL DEFAULT 'active',
    is_main_storage BOOLEAN NOT NULL DEFAULT FALSE,                         -- Designates the primary/main storage for its company_location (if applicable)
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    deleted_at TIMESTAMP WITH TIME ZONE                                     -- Timestamp when status transitioned to 'removed'
);
CREATE UNIQUE INDEX IF NOT EXISTS storages_name_company_location_key_active
    ON public.storages (company_location_id, name)
    WHERE status IN ('active', 'inactive') AND deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS storages_single_main_per_company_location_active
    ON public.storages (company_location_id)
    WHERE is_main_storage = TRUE AND status = 'active' AND deleted_at IS NULL;

CREATE OR REPLACE TRIGGER set_public_storages_updated_at
    BEFORE UPDATE ON public.storages
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.storages IS 'Manages inventory storage locations (e.g., warehouses, shelves, bins) for a tenant company, tied to specific operational company locations.';
COMMENT ON COLUMN public.storages.parent_id IS 'References a parent storage if this storage is part of a hierarchy (e.g., a shelf in an aisle, a bin on a shelf).';
COMMENT ON COLUMN public.storages.type IS 'Categorizes the storage type (e.g., general, scrap, quarantine, transit, returns).';
COMMENT ON COLUMN public.storages.status IS 'Current operational status of the storage: active, inactive (temporarily unavailable), or removed (permanently decommissioned).';
COMMENT ON COLUMN public.storages.is_main_storage IS 'Indicates if this is the primary operational storage for its associated company location (e.g., main warehouse).';
COMMENT ON COLUMN public.storages.deleted_at IS 'Timestamp for soft deletion (when status is ''removed'').';


-- ### `public.storage_permission_types` (Conceptual, for application-level permission definition)
-- This table was listed in blueprint but is more for defining keys for JSONB permissions;
-- actual enforcement is application-level. Included for completeness if used as a lookup by app.
CREATE TABLE IF NOT EXISTS public.storage_permission_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT UNIQUE NOT NULL,       -- The programmatic permission key (e.g., 'view_stock', 'update_stock', 'transfer_out')
    description TEXT NOT NULL,      -- User-friendly description (e.g., 'Ability to view current stock levels.')
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE OR REPLACE TRIGGER set_public_storage_permission_types_updated_at
    BEFORE UPDATE ON public.storage_permission_types
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.storage_permission_types IS 'Defines the available granular permission keys for storage operations. Used for application-level validation and dynamic UI generation for user storage permissions.';
COMMENT ON COLUMN public.storage_permission_types.key IS 'Unique programmatic key for a storage permission.';


-- ### `public.user_storage_permissions`
-- Defines granular permissions for a user on specific storages within a company, and marks one as default.
CREATE TABLE IF NOT EXISTS public.user_storage_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    storage_id UUID NOT NULL REFERENCES public.storages(id) ON DELETE CASCADE,
    permissions JSONB NOT NULL DEFAULT '{}'::jsonb,          -- e.g., {"view_stock": true, "update_stock": false, "can_transfer_out": true} - keys should align with storage_permission_types.key
    is_default_for_user BOOLEAN NOT NULL DEFAULT FALSE,      -- To mark ONE default storage per user (within their accessible storages)
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT user_storage_permissions_unique_per_storage UNIQUE (user_id, storage_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS user_storage_permissions_single_default_per_user
    ON public.user_storage_permissions (user_id)
    WHERE is_default_for_user = TRUE;

CREATE OR REPLACE TRIGGER set_public_user_storage_permissions_updated_at
    BEFORE UPDATE ON public.user_storage_permissions
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.user_storage_permissions IS 'Assigns specific operational permissions for users on individual storage locations and designates a default storage for a user.';
COMMENT ON COLUMN public.user_storage_permissions.permissions IS 'JSONB object defining granular permissions for the user on this storage (e.g., {"view_stock": true, "perform_stock_take": false}). Keys should correspond to `storage_permission_types`.';
COMMENT ON COLUMN public.user_storage_permissions.is_default_for_user IS 'Indicates if this is the user''s default storage location for inventory operations.';


-- ## I.3. Goods Receipt Tables

-- ### `public.goods_receipt_notes` (GRN)
-- Records the receipt of goods into inventory, often against a purchase order.
CREATE TABLE IF NOT EXISTS public.goods_receipt_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    company_location_id UUID NOT NULL REFERENCES public.company_locations(id) ON DELETE RESTRICT, -- Location receiving the goods
    grn_number TEXT NOT NULL,           -- Generated using document_sequence_definitions (type 'GOODS_RECEIPT_NOTES')
    receipt_date DATE NOT NULL DEFAULT CURRENT_DATE, -- Date goods were physically received

    supplier_partner_id UUID NULLABLE REFERENCES public.partners(id) ON DELETE RESTRICT, -- Supplier, if known/applicable
    purchase_order_id UUID NULLABLE REFERENCES public.purchase_orders(id) ON DELETE SET NULL, -- Link to PO if received against one

    -- Delivery Details (Optional)
    supplier_delivery_note_number TEXT NULLABLE, -- Supplier's delivery note/packing slip number
    delivered_by_details TEXT NULLABLE,      -- e.g., Name of courier, driver, vehicle registration

    -- Status & Control
    status public.grn_status_enum NOT NULL DEFAULT 'draft',
    inspected_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL, -- User who performed inspection
    inspection_date DATE NULLABLE,

    notes TEXT NULLABLE,                     -- General notes about the receipt

    -- Audit
    created_by_user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT goods_receipt_notes_company_location_grn_number_key UNIQUE (company_location_id, grn_number)
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_grn_company_id ON public.goods_receipt_notes(company_id);
CREATE INDEX IF NOT EXISTS idx_grn_supplier_partner_id ON public.goods_receipt_notes(supplier_partner_id);
CREATE INDEX IF NOT EXISTS idx_grn_purchase_order_id ON public.goods_receipt_notes(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_grn_grn_number ON public.goods_receipt_notes(company_location_id, grn_number);
CREATE INDEX IF NOT EXISTS idx_grn_receipt_date ON public.goods_receipt_notes(receipt_date);
CREATE INDEX IF NOT EXISTS idx_grn_status ON public.goods_receipt_notes(status);

CREATE OR REPLACE TRIGGER set_public_goods_receipt_notes_updated_at
    BEFORE UPDATE ON public.goods_receipt_notes
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.goods_receipt_notes IS 'Records the receipt of goods into a tenant company''s inventory, often against a purchase order.';
COMMENT ON COLUMN public.goods_receipt_notes.company_location_id IS 'The company location where the goods are being received.';
COMMENT ON COLUMN public.goods_receipt_notes.grn_number IS 'Unique Goods Receipt Note number, generated per company_location_id.';
COMMENT ON COLUMN public.goods_receipt_notes.receipt_date IS 'Date the goods were physically received by the tenant company.';
COMMENT ON COLUMN public.goods_receipt_notes.supplier_partner_id IS 'The supplier from whom the goods were received.';
COMMENT ON COLUMN public.goods_receipt_notes.purchase_order_id IS 'Link to the purchase order, if these goods are being received against a PO.';
COMMENT ON COLUMN public.goods_receipt_notes.supplier_delivery_note_number IS 'The delivery note number or packing slip reference from the supplier.';
COMMENT ON COLUMN public.goods_receipt_notes.status IS 'Current status of the goods receipt process (e.g., draft, completed).';


-- ### `public.goods_receipt_note_items`
-- Stores individual line items received on a Goods Receipt Note.
CREATE TABLE IF NOT EXISTS public.goods_receipt_note_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    goods_receipt_note_id UUID NOT NULL REFERENCES public.goods_receipt_notes(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT, -- Denormalized for RLS
    purchase_order_item_id UUID NULLABLE REFERENCES public.purchase_order_items(id) ON DELETE SET NULL, -- Link to specific PO line

    nomenclature_id UUID NOT NULL REFERENCES public.nomenclatures(id) ON DELETE RESTRICT,

    -- Quantities
    quantity_ordered NUMERIC(15, 5) NULLABLE,    -- Quantity from PO line, for reference during receipt
    quantity_received NUMERIC(15, 5) NOT NULL,
    quantity_accepted NUMERIC(15, 5) NULLABLE,   -- Quantity accepted after inspection (if different from received)
    quantity_rejected NUMERIC(15, 5) NULLABLE,   -- Quantity rejected after inspection
    rejection_reason TEXT NULLABLE,
    unit_id UUID NOT NULL REFERENCES public.nomenclature_unit(id) ON DELETE RESTRICT,

    -- Costing (Actual cost at time of receipt)
    unit_cost_at_receipt NUMERIC(15, 5) NOT NULL, -- Actual cost per unit, excluding reclaimable VAT. This values inventory.
    line_total_cost NUMERIC(15, 5) NOT NULL,      -- Calculated: quantity_accepted * unit_cost_at_receipt (or quantity_received if no separate acceptance step)

    -- Inventory Tracking Details (Crucial for creating/updating inventory_stock_items)
    target_storage_id UUID NOT NULL REFERENCES public.storages(id) ON DELETE RESTRICT, -- Where the accepted goods are placed
    batch_number TEXT NULLABLE,         -- To be filled if nomenclature is batch_tracked
    serial_numbers JSONB NULLABLE,      -- For serial_tracked items: array of received serial numbers e.g., ["SN101", "SN102"]
    expiry_date DATE NULLABLE,          -- Expiry date, often tied to batch

    notes TEXT NULLABLE,                -- Notes specific to this received item

    -- Audit
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT check_grn_item_quantities_non_negative CHECK (quantity_received >= 0 AND COALESCE(quantity_accepted,0) >=0 AND COALESCE(quantity_rejected,0)>=0),
    CONSTRAINT check_grn_item_acceptance_logic CHECK (
        (quantity_accepted IS NULL AND quantity_rejected IS NULL) OR -- No inspection step yet or not used
        (quantity_accepted IS NOT NULL AND quantity_rejected IS NOT NULL AND ROUND(quantity_received,5) = ROUND(quantity_accepted + quantity_rejected,5)) OR
        (quantity_accepted IS NOT NULL AND quantity_rejected IS NULL AND ROUND(quantity_received,5) = ROUND(quantity_accepted,5)) OR -- All accepted
        (quantity_rejected IS NOT NULL AND quantity_accepted IS NULL AND ROUND(quantity_received,5) = ROUND(quantity_rejected,5))  -- All rejected
    ),
    CONSTRAINT check_grn_item_line_total_cost CHECK (
        -- This should be (COALESCE(quantity_accepted, quantity_received)) * unit_cost_at_receipt if quantity_accepted can be null when all are received.
        -- Assuming line_total_cost is based on the quantity that effectively increases stock value.
        ROUND(line_total_cost, 5) = ROUND(COALESCE(quantity_accepted, quantity_received) * unit_cost_at_receipt, 5)
    )
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_grn_items_grn_id ON public.goods_receipt_note_items(goods_receipt_note_id);
CREATE INDEX IF NOT EXISTS idx_grn_items_company_id ON public.goods_receipt_note_items(company_id);
CREATE INDEX IF NOT EXISTS idx_grn_items_po_item_id ON public.goods_receipt_note_items(purchase_order_item_id);
CREATE INDEX IF NOT EXISTS idx_grn_items_nomenclature_id ON public.goods_receipt_note_items(nomenclature_id);
CREATE INDEX IF NOT EXISTS idx_grn_items_target_storage_id ON public.goods_receipt_note_items(target_storage_id);

CREATE OR REPLACE TRIGGER set_public_goods_receipt_note_items_updated_at
    BEFORE UPDATE ON public.goods_receipt_note_items
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.goods_receipt_note_items IS 'Stores individual line items received on a Goods Receipt Note, including quantities, costs, and inventory tracking details like batch/serial numbers.';
COMMENT ON COLUMN public.goods_receipt_note_items.purchase_order_item_id IS 'Link to the original purchase order item, if this receipt is against a PO.';
COMMENT ON COLUMN public.goods_receipt_note_items.nomenclature_id IS 'The catalog item being received.';
COMMENT ON COLUMN public.goods_receipt_note_items.quantity_ordered IS 'Quantity originally ordered on the PO line (for reference during receipt process).';
COMMENT ON COLUMN public.goods_receipt_note_items.quantity_received IS 'Actual quantity physically received from the supplier for this item.';
COMMENT ON COLUMN public.goods_receipt_note_items.quantity_accepted IS 'Quantity accepted into inventory after inspection. If null, assume quantity_received is accepted for stock valuation if no rejection.';
COMMENT ON COLUMN public.goods_receipt_note_items.quantity_rejected IS 'Quantity rejected during inspection.';
COMMENT ON COLUMN public.goods_receipt_note_items.unit_cost_at_receipt IS 'Actual cost per unit for the received items (excluding reclaimable VAT). This value is used for inventory valuation.';
COMMENT ON COLUMN public.goods_receipt_note_items.line_total_cost IS 'Total cost for the accepted/received quantity of this item (COALESCE(quantity_accepted, quantity_received) * unit_cost_at_receipt). This is value added to inventory.';
COMMENT ON COLUMN public.goods_receipt_note_items.target_storage_id IS 'The specific storage location where the accepted goods are being placed.';
COMMENT ON COLUMN public.goods_receipt_note_items.batch_number IS 'Batch or lot number recorded for the received items, if applicable (for batch_tracked nomenclatures).';
COMMENT ON COLUMN public.goods_receipt_note_items.serial_numbers IS 'JSONB array of unique serial numbers for serial-tracked items received on this line. E.g., ["SN001", "SN002"].';
COMMENT ON COLUMN public.goods_receipt_note_items.expiry_date IS 'Expiry date for the received batch/items, if applicable.';


-- ## I.4. Core Stock and Allocation Tables

-- ### `public.inventory_stock_items`
-- Represents specific, identifiable instances or aggregations of stock for a nomenclature
-- in a storage location, including cost, tracking details (batch/serial), and optional item-specific selling prices.
CREATE TABLE IF NOT EXISTS public.inventory_stock_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    nomenclature_id UUID NOT NULL REFERENCES public.nomenclatures(id) ON DELETE RESTRICT,
    storage_id UUID NOT NULL REFERENCES public.storages(id) ON DELETE RESTRICT, -- Specific storage location (e.g. bin, shelf)

    source_document_type TEXT NULLABLE, -- e.g., 'GOODS_RECEIPT_NOTE_ITEM', 'SALES_RETURN_ITEM', 'STOCK_ADJUSTMENT'
    source_document_item_id UUID NULLABLE, -- ID of the line item on the source document that created/updated this stock item

    batch_number TEXT NULLABLE,     -- Batch/Lot number if nomenclature is batch_tracked
    serial_number TEXT NULLABLE,    -- Unique serial number if nomenclature is serial_tracked
    expiry_date DATE NULLABLE,      -- Expiry date, often associated with batches

    quantity_on_hand NUMERIC(15, 5) NOT NULL DEFAULT 0.00000, -- Current available quantity for this specific stock item record
    original_intake_quantity NUMERIC(15, 5) NOT NULL, -- Quantity when this stock item record was first created (e.g., from GRN)

    cost_price_per_unit NUMERIC(15, 5) NOT NULL, -- Cost price at intake, used for COGS calculation (FIFO, LIFO, Avg based on app logic)

    -- Item-Specific Selling Price (Optional - overrides nomenclature/other pricing rules if set for this specific batch/serial)
    selling_price_exclusive_vat NUMERIC(15,5) NULLABLE,
    selling_price_inclusive_vat NUMERIC(15,5) NULLABLE,
    selling_price_currency_id UUID NULLABLE REFERENCES public.currencies(id) ON DELETE RESTRICT,
    selling_price_vat_rule_id UUID NULLABLE REFERENCES public.vat_rules_and_exemptions(id) ON DELETE RESTRICT,

    status public.inventory_stock_item_status_enum NOT NULL DEFAULT 'available',
    bin_location_code TEXT NULLABLE, -- More specific location within the storage (e.g., "Shelf A-1", "Bin 003")
    first_received_at TIMESTAMP WITH TIME ZONE NOT NULL, -- Timestamp when this stock (batch/serial) first entered inventory
    last_movement_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(), -- Timestamp of the last movement affecting this stock item

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    -- For serial_tracked items, (company_id, nomenclature_id, serial_number) must be unique across non-consumed statuses
    CONSTRAINT inventory_stock_items_company_nomenclature_serial_unique
        UNIQUE (company_id, nomenclature_id, serial_number)
        WHERE serial_number IS NOT NULL AND status <> 'dispatched' AND status <> 'consumed_in_production' AND status <> 'returned_to_supplier' AND status <> 'written_off',

    -- A given batch of a nomenclature in a specific storage should ideally be one record if quantity_only or batch_tracked without serials
    -- This is harder to enforce with a simple constraint if multiple GRNs bring in same batch. App logic manages aggregation or distinct records.
    -- For now, no UNIQUE constraint on (company_id, nomenclature_id, storage_id, batch_number) to allow flexibility.

    CONSTRAINT check_isi_quantity_logic CHECK (
        ( (EXISTS (SELECT 1 FROM public.nomenclatures n WHERE n.id = nomenclature_id AND n.inventory_tracking_type = 'serial_tracked')) AND
          quantity_on_hand IN (0, 1) AND original_intake_quantity = 1 AND serial_number IS NOT NULL ) OR
        ( (EXISTS (SELECT 1 FROM public.nomenclatures n WHERE n.id = nomenclature_id AND n.inventory_tracking_type <> 'serial_tracked')) AND
          quantity_on_hand >= 0 )
    ),
    CONSTRAINT check_isi_tracking_identifiers_from_nomenclature CHECK (
        ( (EXISTS (SELECT 1 FROM public.nomenclatures n WHERE n.id = nomenclature_id AND n.inventory_tracking_type = 'serial_tracked')) AND serial_number IS NOT NULL ) OR
        ( (EXISTS (SELECT 1 FROM public.nomenclatures n WHERE n.id = nomenclature_id AND n.inventory_tracking_type = 'batch_tracked')) AND batch_number IS NOT NULL AND serial_number IS NULL ) OR
        ( (EXISTS (SELECT 1 FROM public.nomenclatures n WHERE n.id = nomenclature_id AND n.inventory_tracking_type = 'quantity_only')) ) OR -- Batch/Serial can be null
        ( (EXISTS (SELECT 1 FROM public.nomenclatures n WHERE n.id = nomenclature_id AND n.inventory_tracking_type = 'none')) AND serial_number IS NULL AND batch_number IS NULL AND quantity_on_hand = 0 )
    ),
    CONSTRAINT check_isi_selling_price_consistency CHECK (
        ( (selling_price_exclusive_vat IS NOT NULL OR selling_price_inclusive_vat IS NOT NULL) AND
          selling_price_currency_id IS NOT NULL AND selling_price_vat_rule_id IS NOT NULL ) OR
        ( selling_price_exclusive_vat IS NULL AND selling_price_inclusive_vat IS NULL AND
          selling_price_currency_id IS NULL AND selling_price_vat_rule_id IS NULL )
    )
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_isi_company_id ON public.inventory_stock_items(company_id);
CREATE INDEX IF NOT EXISTS idx_isi_nomenclature_id ON public.inventory_stock_items(nomenclature_id);
CREATE INDEX IF NOT EXISTS idx_isi_storage_id ON public.inventory_stock_items(storage_id);
CREATE INDEX IF NOT EXISTS idx_isi_batch_number ON public.inventory_stock_items(company_id, nomenclature_id, batch_number) WHERE batch_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_isi_serial_number_search ON public.inventory_stock_items(company_id, nomenclature_id, serial_number) WHERE serial_number IS NOT NULL; -- For searching
CREATE INDEX IF NOT EXISTS idx_isi_status ON public.inventory_stock_items(status);
CREATE INDEX IF NOT EXISTS idx_isi_expiry_date ON public.inventory_stock_items(expiry_date) WHERE expiry_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_isi_source_doc_item_id ON public.inventory_stock_items(source_document_item_id, source_document_type) WHERE source_document_item_id IS NOT NULL;

CREATE OR REPLACE TRIGGER set_public_inventory_stock_items_updated_at
    BEFORE UPDATE ON public.inventory_stock_items
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.inventory_stock_items IS 'Represents specific, identifiable instances or aggregations of stock for a nomenclature in a storage location, including cost, tracking details (batch/serial), status, and optional item-specific selling prices.';
COMMENT ON COLUMN public.inventory_stock_items.storage_id IS 'The specific storage location (e.g., warehouse, shelf, bin) where this stock item resides.';
COMMENT ON COLUMN public.inventory_stock_items.source_document_type IS 'Type of document that created this stock item (e.g., ''GOODS_RECEIPT_NOTE_ITEM'').';
COMMENT ON COLUMN public.inventory_stock_items.source_document_item_id IS 'ID of the line item on the source document that created this stock item.';
COMMENT ON COLUMN public.inventory_stock_items.batch_number IS 'Batch or lot number if the nomenclature is batch-tracked.';
COMMENT ON COLUMN public.inventory_stock_items.serial_number IS 'Unique serial number if the nomenclature is serial-tracked. Each serial-tracked item has its own record.';
COMMENT ON COLUMN public.inventory_stock_items.expiry_date IS 'Expiry date of the batch or serial item.';
COMMENT ON COLUMN public.inventory_stock_items.quantity_on_hand IS 'Current available quantity for this specific stock item record. For serial-tracked, this is 0 or 1.';
COMMENT ON COLUMN public.inventory_stock_items.original_intake_quantity IS 'Quantity when this stock item record was initially created/received. For serial-tracked, this is 1.';
COMMENT ON COLUMN public.inventory_stock_items.cost_price_per_unit IS 'Cost price per unit at the time of intake. Used for COGS calculations.';
COMMENT ON COLUMN public.inventory_stock_items.selling_price_exclusive_vat IS 'Specific selling price (excluding VAT) for this individual stock item (e.g., specific serial/batch), overriding other prices.';
COMMENT ON COLUMN public.inventory_stock_items.selling_price_inclusive_vat IS 'Specific selling price (including VAT) for this individual stock item.';
COMMENT ON COLUMN public.inventory_stock_items.status IS 'Current availability status of this stock item (e.g., available, allocated, damaged).';
COMMENT ON COLUMN public.inventory_stock_items.bin_location_code IS 'More granular location within the parent storage (e.g., specific bin or shelf code).';
COMMENT ON COLUMN public.inventory_stock_items.first_received_at IS 'Timestamp when this specific stock (batch/serial) first entered the inventory system.';
COMMENT ON COLUMN public.inventory_stock_items.last_movement_at IS 'Timestamp of the last recorded movement or status change affecting this stock item.';


-- ### `public.stock_allocations`
-- Links demand document items (e.g., sales order items) to specific inventory stock items,
-- representing reservation or allocation of stock.
CREATE TABLE IF NOT EXISTS public.stock_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,

    -- Demand Side (What needs the stock)
    sales_order_item_id UUID NULLABLE REFERENCES public.sales_order_items(id) ON DELETE CASCADE,
    -- production_order_component_id UUID NULLABLE, -- Placeholder for future Manufacturing module
    -- transfer_order_item_id UUID NULLABLE,      -- Placeholder for future Stock Transfer module

    -- Supply Side (Which specific stock is allocated)
    inventory_stock_item_id UUID NOT NULL REFERENCES public.inventory_stock_items(id) ON DELETE RESTRICT,
    quantity_allocated NUMERIC(15, 5) NOT NULL CHECK (quantity_allocated > 0),
    quantity_fulfilled_from_this_allocation NUMERIC(15, 5) NOT NULL DEFAULT 0.00000 CHECK (quantity_fulfilled_from_this_allocation >=0),

    status public.stock_allocation_status_enum NOT NULL DEFAULT 'active_allocation',
    allocated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    last_fulfilled_at TIMESTAMP WITH TIME ZONE NULLABLE, -- When stock was last dispatched/consumed against this allocation

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),

    CONSTRAINT check_allocation_demand_source CHECK (
        num_nonnulls(sales_order_item_id /*, production_order_component_id, transfer_order_item_id */) = 1 -- Ensures one demand source
    ),
    CONSTRAINT check_allocation_fulfilled_qty CHECK (quantity_fulfilled_from_this_allocation <= quantity_allocated),
    -- UNIQUE constraint to prevent allocating the same stock item multiple times to the exact same demand line,
    -- unless an allocation can be split and re-linked.
    CONSTRAINT stock_allocations_demand_supply_unique UNIQUE (sales_order_item_id, inventory_stock_item_id)
    -- Consider if production_order_component_id etc. should be part of this unique key if they are added
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_sa_company_id ON public.stock_allocations(company_id);
CREATE INDEX IF NOT EXISTS idx_sa_sales_order_item_id ON public.stock_allocations(sales_order_item_id) WHERE sales_order_item_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sa_inventory_stock_item_id ON public.stock_allocations(inventory_stock_item_id);
CREATE INDEX IF NOT EXISTS idx_sa_status ON public.stock_allocations(status);

CREATE OR REPLACE TRIGGER set_public_stock_allocations_updated_at
    BEFORE UPDATE ON public.stock_allocations
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.stock_allocations IS 'Links demand document items (e.g., sales order items) to specific inventory_stock_items, representing reservation or allocation of stock.';
COMMENT ON COLUMN public.stock_allocations.sales_order_item_id IS 'Reference to the sales order item for which stock is being allocated.';
COMMENT ON COLUMN public.stock_allocations.inventory_stock_item_id IS 'Reference to the specific inventory_stock_item record being allocated.';
COMMENT ON COLUMN public.stock_allocations.quantity_allocated IS 'The quantity from the inventory_stock_item that is allocated/reserved for the demand item.';
COMMENT ON COLUMN public.stock_allocations.quantity_fulfilled_from_this_allocation IS 'The quantity from this specific allocation that has been dispatched/consumed.';
COMMENT ON COLUMN public.stock_allocations.status IS 'Status of this specific stock allocation (e.g., active_allocation, fulfilled, cancelled).';


-- ## I.5. Stock Auditing Table

-- ### `public.stock_movements_log`
-- Audits all changes to inventory stock items, including quantity adjustments and status changes.
CREATE TABLE IF NOT EXISTS public.stock_movements_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,

    inventory_stock_item_id UUID NOT NULL REFERENCES public.inventory_stock_items(id) ON DELETE RESTRICT, -- The specific stock item affected
    nomenclature_id UUID NOT NULL REFERENCES public.nomenclatures(id) ON DELETE RESTRICT, -- Denormalized for easier querying/reporting
    storage_id UUID NOT NULL REFERENCES public.storages(id) ON DELETE RESTRICT,           -- Denormalized for easier querying/reporting

    movement_type public.stock_movement_type_enum NOT NULL,
    movement_datetime TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(), -- Exact timestamp of the movement/event
    quantity_changed NUMERIC(15, 5) NOT NULL DEFAULT 0.00000,
        -- Positive for increases in on-hand, negative for decreases. Zero if only status change.

    quantity_before_movement NUMERIC(15, 5) NULLABLE, -- Quantity on hand of the inventory_stock_item BEFORE this movement
    quantity_after_movement NUMERIC(15, 5) NULLABLE,  -- Quantity on hand of the inventory_stock_item AFTER this movement

    status_before_movement public.inventory_stock_item_status_enum NULLABLE, -- Status of inventory_stock_item BEFORE
    status_after_movement public.inventory_stock_item_status_enum NULLABLE,  -- Status of inventory_stock_item AFTER

    cost_price_per_unit_at_movement NUMERIC(15,5) NULLABLE, -- Cost price of the items moved (especially for outgoing COGS)

    -- Source of the Movement (links to the business document/event that triggered it)
    source_document_type TEXT NULLABLE,
        -- e.g., 'GOODS_RECEIPT_NOTE_ITEM', 'SALES_ORDER_ITEM' (for allocation status change),
        -- 'INVOICE_ITEM' (for dispatch), 'CREDIT_NOTE_ITEM' (for sales return),
        -- 'STOCK_ADJUSTMENT', 'PRODUCTION_ORDER_COMPONENT', 'PRODUCTION_ORDER_OUTPUT', 'STOCK_TRANSFER_ORDER_ITEM'
    source_document_id UUID NULLABLE,       -- ID of the header document (e.g., goods_receipt_notes.id)
    source_document_item_id UUID NULLABLE,  -- ID of the item line on the document (e.g., goods_receipt_note_items.id)

    user_id UUID NULLABLE REFERENCES public.users(id) ON DELETE SET NULL, -- User who initiated/processed the action causing movement
    notes TEXT NULLABLE,                    -- Any specific notes related to this movement
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
    -- No updated_at as log entries are typically immutable once created.
);
-- Indexes
CREATE INDEX IF NOT EXISTS idx_sml_company_id ON public.stock_movements_log(company_id);
CREATE INDEX IF NOT EXISTS idx_sml_inventory_stock_item_id ON public.stock_movements_log(inventory_stock_item_id);
CREATE INDEX IF NOT EXISTS idx_sml_nomenclature_id_storage_id ON public.stock_movements_log(nomenclature_id, storage_id); -- Common query
CREATE INDEX IF NOT EXISTS idx_sml_movement_type ON public.stock_movements_log(movement_type);
CREATE INDEX IF NOT EXISTS idx_sml_movement_datetime ON public.stock_movements_log(movement_datetime DESC); -- Often queried by recent time
CREATE INDEX IF NOT EXISTS idx_sml_source_document ON public.stock_movements_log(source_document_type, source_document_id, source_document_item_id);
CREATE INDEX IF NOT EXISTS idx_sml_user_id ON public.stock_movements_log(user_id);

COMMENT ON TABLE public.stock_movements_log IS 'Audits all changes to inventory stock items, including quantity adjustments and status changes, enabling point-in-time stock reporting for tenant companies.';
COMMENT ON COLUMN public.stock_movements_log.inventory_stock_item_id IS 'The specific inventory_stock_item record that was affected by this movement.';
COMMENT ON COLUMN public.stock_movements_log.nomenclature_id IS 'Denormalized nomenclature_id of the affected stock item for easier reporting.';
COMMENT ON COLUMN public.stock_movements_log.storage_id IS 'Denormalized storage_id where the movement occurred for easier reporting.';
COMMENT ON COLUMN public.stock_movements_log.movement_type IS 'The type of inventory transaction or event that occurred.';
COMMENT ON COLUMN public.stock_movements_log.movement_datetime IS 'The precise date and time the stock movement or status change was recorded.';
COMMENT ON COLUMN public.stock_movements_log.quantity_changed IS 'The change in on-hand quantity for the stock item. Positive for increases, negative for decreases. Zero if only a status change.';
COMMENT ON COLUMN public.stock_movements_log.quantity_before_movement IS 'Snapshot of the quantity_on_hand of the inventory_stock_item immediately before this movement.';
COMMENT ON COLUMN public.stock_movements_log.quantity_after_movement IS 'Snapshot of the quantity_on_hand of the inventory_stock_item immediately after this movement.';
COMMENT ON COLUMN public.stock_movements_log.status_before_movement IS 'Snapshot of the status of the inventory_stock_item immediately before this event.';
COMMENT ON COLUMN public.stock_movements_log.status_after_movement IS 'Snapshot of the status of the inventory_stock_item immediately after this event.';
COMMENT ON COLUMN public.stock_movements_log.cost_price_per_unit_at_movement IS 'The cost price per unit of the items involved in this movement, crucial for COGS valuation of outgoing stock.';
COMMENT ON COLUMN public.stock_movements_log.source_document_type IS 'The type of business document that triggered this stock movement (e.g., INVOICE_ITEM, GOODS_RECEIPT_NOTE_ITEM).';
COMMENT ON COLUMN public.stock_movements_log.source_document_id IS 'The ID of the header of the source document.';
COMMENT ON COLUMN public.stock_movements_log.source_document_item_id IS 'The ID of the specific line item on the source document related to this movement.';
COMMENT ON COLUMN public.stock_movements_log.user_id IS 'The user who initiated or processed the action that resulted in this stock movement.';


-- #############################################################################
-- # J. SaaS Platform Management Module (For Hyper M v2 Itself)
-- #############################################################################
-- This module defines the structure for managing SaaS subscription plans,
-- features, feature gating, and tenant company subscriptions to the Hyper M v2
-- platform itself.

-- ## J.1. ENUM Types for SaaS Platform Management (continued)

CREATE TYPE public.saas_plan_type_enum AS ENUM (
    'CLOUD',                -- Standard multi-tenant cloud offering
    'COMMUNITY_EDITION',    -- Free, self-hosted community version
    'ENTERPRISE_SELF_HOSTED' -- Licensed, self-hosted enterprise version
);

COMMENT ON TYPE public.saas_plan_type_enum IS 'Defines the different categories of SaaS plans offered by Hyper M v2.';

CREATE TYPE public.saas_feature_status_enum AS ENUM (
    'EXPERIMENTAL_CE',      -- Feature is new, primarily for testing in Community Edition
    'BETA_CLOUD',           -- Feature is in beta, available on select Cloud plans for broader testing
    'STABLE',               -- Feature is stable and generally available on relevant plans
    'PREMIUM',              -- Feature is stable and considered a premium offering
    'ENTERPRISE_ONLY',      -- Feature is stable and typically reserved for Enterprise Edition
    'DEPRECATED',           -- Feature is being phased out
    'INTERNAL_ALPHA'        -- Feature is in early internal testing, not yet public
);

COMMENT ON TYPE public.saas_feature_status_enum IS 'Defines the development and availability status of a SaaS feature.';

CREATE TYPE public.company_saas_subscription_status_enum AS ENUM (
    'trialing',             -- Company is currently in a free trial period.
    'trial_expired',        -- Trial period has ended, awaiting plan selection/payment.
    'active',               -- Subscription is active and paid (or on a free plan that's active).
    'past_due',             -- Payment for the current billing period is overdue.
    'payment_failed',       -- Last payment attempt failed.
    'pending_cancellation', -- User has requested cancellation, effective at end of current period.
    'cancelled',            -- Subscription has been cancelled and is no longer active (e.g., after grace period or non-renewal).
    'pending_activation',   -- For scenarios where a plan is selected but payment is pending (e.g., bank wire) before activation.
    'incomplete',           -- Initial setup or plan selection process was started but not fully completed.
    'free_tier_active'      -- Company is on a specific "Free Tier" plan (often after downgrade from a paid plan).
);

COMMENT ON TYPE public.company_saas_subscription_status_enum IS 'Defines the lifecycle status of a tenant company''s subscription to the Hyper M v2 platform.';


-- ## J.2. Core Tables for SaaS Platform Management

-- ### `public.saas_plans`
-- Defines the various subscription plans offered for the Hyper M v2 platform.
CREATE TABLE IF NOT EXISTS public.saas_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_key TEXT UNIQUE NOT NULL,                   -- Programmatic key, e.g., 'FREE_TIER', 'CLOUD_BASIC', 'CE_BASE', 'EE_STANDARD'
    name TEXT NOT NULL,                              -- User-friendly name, e.g., "Free Tier", "Cloud Basic Plan"
    description TEXT,
    plan_type public.saas_plan_type_enum NOT NULL,   -- Type of plan (Cloud, CE, EE)
    is_publicly_selectable BOOLEAN NOT NULL DEFAULT TRUE, -- If TRUE, users can typically select this plan themselves (e.g., from a pricing page). EE plans might be FALSE.
    is_active BOOLEAN NOT NULL DEFAULT TRUE,         -- If FALSE, this plan cannot be newly subscribed to.
    -- Billing Details (primarily for CLOUD plans)
    billing_interval_months INTEGER,                 -- e.g., 1 (monthly), 12 (annually). NULL for non-billed plans (Free, CE).
    price_per_interval_exclusive_vat NUMERIC(15, 5), -- Price per billing interval. NULL for free plans.
    currency_id UUID REFERENCES public.currencies(id) ON DELETE RESTRICT, -- Currency of the price.
    -- Trial & Grace Period Details
    trial_days_offered INTEGER NOT NULL DEFAULT 0,   -- Number of trial days offered for this plan, if it can be a trial.
    grace_period_days_after_payment_due INTEGER NOT NULL DEFAULT 0, -- Days after a due payment fails before subscription status changes (e.g., to 'past_due' or triggers downgrade).
    -- Downgrade Path
    downgrades_to_plan_id UUID REFERENCES public.saas_plans(id) ON DELETE SET NULL, -- Plan to automatically downgrade to on non-payment or cancellation of a paid plan (e.g., to a Free Tier).
    display_order INTEGER NOT NULL DEFAULT 0,        -- For ordering plans in UI listings.
    -- Audit fields
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT check_saas_plan_billing_details CHECK (
        (price_per_interval_exclusive_vat IS NOT NULL AND currency_id IS NOT NULL AND billing_interval_months IS NOT NULL AND billing_interval_months > 0) OR
        (price_per_interval_exclusive_vat IS NULL AND currency_id IS NULL AND billing_interval_months IS NULL)
    ),
    CONSTRAINT check_saas_plan_trial_days CHECK (trial_days_offered >= 0),
    CONSTRAINT check_saas_plan_grace_period_days CHECK (grace_period_days_after_payment_due >= 0),
    CONSTRAINT check_saas_plan_downgrade_not_self CHECK (id <> downgrades_to_plan_id OR downgrades_to_plan_id IS NULL)
);

CREATE OR REPLACE TRIGGER set_public_saas_plans_updated_at
    BEFORE UPDATE ON public.saas_plans
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.saas_plans IS 'Defines the subscription plans available for the Hyper M v2 SaaS platform itself, including pricing, billing cycle, and type (Cloud, CE, EE).';
COMMENT ON COLUMN public.saas_plans.plan_key IS 'Unique programmatic identifier for the plan (e.g., ''CLOUD_PREMIUM'', ''EE_UNLIMITED'').';
COMMENT ON COLUMN public.saas_plans.name IS 'User-friendly display name of the plan.';
COMMENT ON COLUMN public.saas_plans.plan_type IS 'Categorizes the plan: CLOUD, COMMUNITY_EDITION, or ENTERPRISE_SELF_HOSTED.';
COMMENT ON COLUMN public.saas_plans.is_publicly_selectable IS 'Indicates if users can generally select this plan from a public list (e.g., pricing page).';
COMMENT ON COLUMN public.saas_plans.is_active IS 'Indicates if the plan is currently active and can be subscribed to or renewed.';
COMMENT ON COLUMN public.saas_plans.billing_interval_months IS 'The number of months in one billing cycle for this plan (e.g., 1 for monthly, 12 for annual). NULL for non-recurring or free plans.';
COMMENT ON COLUMN public.saas_plans.price_per_interval_exclusive_vat IS 'The price for one billing interval, excluding VAT. NULL for free plans.';
COMMENT ON COLUMN public.saas_plans.currency_id IS 'The currency of the price_per_interval. FK to public.currencies. NULL for free plans.';
COMMENT ON COLUMN public.saas_plans.trial_days_offered IS 'Number of free trial days offered when a company first subscribes to this plan or if this plan is the default trial plan.';
COMMENT ON COLUMN public.saas_plans.grace_period_days_after_payment_due IS 'Number of days a subscription can remain active after a payment is due but not successfully processed, before triggering further actions (e.g., downgrade).';
COMMENT ON COLUMN public.saas_plans.downgrades_to_plan_id IS 'The ID of the plan to which a subscription will be automatically downgraded (e.g., to a Free Tier) if a paid plan is not renewed or payment fails persistently. Can be NULL if no auto-downgrade path.';
COMMENT ON COLUMN public.saas_plans.display_order IS 'Integer used to sort plans for display in user interfaces (e.g., pricing tables).';


-- ### `public.features`
-- Master list of all distinct, gateable features within the Hyper M v2 platform.
-- These features can be associated with different SaaS plans.
CREATE TABLE IF NOT EXISTS public.features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_key TEXT UNIQUE NOT NULL,                -- Programmatic key, e.g., 'CORE_ACCOUNTING', 'MULTI_WAREHOUSE', 'API_ACCESS_BASIC', 'ADVANCED_REPORTING_BUILDER'
    name TEXT NOT NULL,                              -- User-friendly name of the feature, e.g., "Core Accounting Module", "Multi-Warehouse Inventory"
    description TEXT,                                -- Detailed description of what the feature enables.
    module_group TEXT,                               -- Optional: Grouping for features, e.g., 'Inventory', 'Sales', 'Administration', 'Integrations'.
    -- This is for organizational purposes in admin UIs or documentation.
    status public.saas_feature_status_enum NOT NULL DEFAULT 'STABLE', -- Current status of the feature.
    -- Default limits/values (can be overridden by saas_plan_features or company_feature_settings)
    default_limit_value NUMERIC NULLABLE,            -- For features with a quantifiable limit (e.g., 1000 API calls, 5 users). NULL if simple on/off.
    default_limit_unit TEXT NULLABLE,                -- Unit for the limit (e.g., 'users', 'api_calls_per_day', 'gb_storage').
    is_core_feature BOOLEAN NOT NULL DEFAULT FALSE,  -- True if this feature is fundamental and expected in most basic plans (e.g., login, basic company setup).
    -- Might affect how "free" or "CE base" tiers are defined.
    availability_notes TEXT,                         -- Internal notes regarding specific availability constraints or future plans for this feature.
    -- Audit fields
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE OR REPLACE TRIGGER set_public_features_updated_at
    BEFORE UPDATE ON public.features
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.features IS 'Master catalog of all gateable features within the Hyper M v2 platform, used for defining plan capabilities.';
COMMENT ON COLUMN public.features.feature_key IS 'Unique, machine-readable key used by the application to check for feature enablement (e.g., ''USER_ROLES_ADVANCED'').';
COMMENT ON COLUMN public.features.name IS 'Human-readable name for the feature, displayed in plan comparisons or admin UIs.';
COMMENT ON COLUMN public.features.description IS 'Explanation of the feature''s functionality and benefits.';
COMMENT ON COLUMN public.features.module_group IS 'An optional category or module the feature belongs to, for organizational purposes (e.g., "CRM", "Inventory", "Reporting").';
COMMENT ON COLUMN public.features.status IS 'Current development or release status of the feature (e.g., EXPERIMENTAL_CE, STABLE, PREMIUM).';
COMMENT ON COLUMN public.features.default_limit_value IS 'A default numeric limit associated with the feature (e.g., number of users, API calls). NULL for simple on/off features. Can be overridden per plan.';
COMMENT ON COLUMN public.features.default_limit_unit IS 'The unit for the default_limit_value (e.g., "items", "records_per_month").';
COMMENT ON COLUMN public.features.is_core_feature IS 'Indicates if this is a fundamental feature, typically included even in basic or free offerings.';
COMMENT ON COLUMN public.features.availability_notes IS 'Internal administrative notes about the feature''s rollout, dependencies, or future considerations.';


-- ### public.saas_plan_features 
-- Links SaaS plans to specific features, defining what capabilities are included in each plan. 
-- It also allows overriding default feature limits on a per-plan basis. 
CREATE TABLE IF NOT EXISTS public.saas_plan_features ( 
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), 
  saas_plan_id UUID NOT NULL REFERENCES public.saas_plans(id) ON DELETE CASCADE, 
  feature_id UUID NOT NULL REFERENCES public.features(id) ON DELETE CASCADE,
  -- Plan-specific enablement and limits for the feature
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE,       -- Whether this feature is enabled for this plan. Can be FALSE to explicitly disable an inherited/core feature for a specific plan.
  -- Plan-specific limit override. If NULL, the default_limit_value from 'features' table (if any) applies.
  -- If features.default_limit_value is NULL (on/off feature), these should also ideally be NULL or not applicable.
  limit_value NUMERIC NULLABLE,                   -- e.g., Plan 'Basic' allows 5 'users' (feature_key='MAX_USERS'), Plan 'Premium' allows 50.
  -- Unit is implicitly taken from features.default_limit_unit.
  -- Additional plan-specific configuration for the feature (flexible JSONB)
  -- e.g., {"api_rate_limit_per_second": 10} for an API access feature on a particular plan.
  -- e.g., {"allowed_integrations": ["xero", "quickbooks"]} for an integrations feature.
  configuration JSONB NULLABLE,
  -- Audit fields
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT saas_plan_features_plan_feature_unique UNIQUE (saas_plan_id, feature_id) -- Ensures a feature is linked only once to a specific plan.
);

CREATE OR REPLACE TRIGGER set_public_saas_plan_features_updated_at BEFORE UPDATE ON public.saas_plan_features FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.saas_plan_features IS 'Defines the specific features included in each SaaS plan and any plan-specific limits or configurations for those features.'; 
COMMENT ON COLUMN public.saas_plan_features.saas_plan_id IS 'Reference to the SaaS plan.'; 
COMMENT ON COLUMN public.saas_plan_features.feature_id IS 'Reference to the feature included in the plan.'; 
COMMENT ON COLUMN public.saas_plan_features.is_enabled IS 'Indicates if this feature is actively enabled for this specific plan. Allows explicitly disabling a feature even if generally available.'; 
COMMENT ON COLUMN public.saas_plan_features.limit_value IS 'Plan-specific override for a quantifiable feature limit (e.g., number of users, API calls). If NULL, the default from the ''features'' table is used. Unit is defined in ''features.default_limit_unit''.'; 
COMMENT ON COLUMN public.saas_plan_features.configuration IS 'JSONB field for additional plan-specific configurations related to this feature (e.g., specific settings, allowed values for a feature on this plan).';


-- ### `public.company_saas_subscriptions`
-- Tracks the SaaS subscription of each tenant company to the Hyper M v2 platform.
CREATE TABLE IF NOT EXISTS public.company_saas_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL UNIQUE REFERENCES public.companies(id) ON DELETE CASCADE, -- Each company has one active SaaS subscription record.
    saas_plan_id UUID NOT NULL REFERENCES public.saas_plans(id) ON DELETE RESTRICT,    -- The current plan the company is subscribed to.
    status public.company_saas_subscription_status_enum NOT NULL DEFAULT 'incomplete',
    -- Trial Period Details
    trial_started_at TIMESTAMP WITH TIME ZONE NULLABLE,
    trial_ends_at TIMESTAMP WITH TIME ZONE NULLABLE,            -- Actual date/time when the trial period ends/ended.
    -- Current Billing Cycle Details (for paid plans)
    current_billing_period_starts_at TIMESTAMP WITH TIME ZONE NULLABLE,
    current_billing_period_ends_at TIMESTAMP WITH TIME ZONE NULLABLE,
    next_billing_date DATE NULLABLE,                        -- The date the next invoice/payment is due for renewal.
    -- Payment Details
    last_payment_attempted_at TIMESTAMP WITH TIME ZONE NULLABLE,
    last_payment_succeeded_at TIMESTAMP WITH TIME ZONE NULLABLE,
    last_payment_failed_reason TEXT NULLABLE,
    -- Cancellation Details
    cancellation_requested_at TIMESTAMP WITH TIME ZONE NULLABLE,
    cancellation_effective_at TIMESTAMP WITH TIME ZONE NULLABLE, -- When the subscription will actually be cancelled (e.g., end of current paid period).
    cancellation_reason TEXT NULLABLE,
    -- Notes & Metadata
    notes TEXT NULLABLE,                                    -- Administrative notes about this subscription.
    metadata JSONB NULLABLE,                                -- For storing additional structured information, e.g., payment gateway subscription ID.
    -- Audit fields
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT check_company_saas_subscription_trial_dates CHECK (
        (trial_started_at IS NOT NULL AND trial_ends_at IS NOT NULL AND trial_ends_at > trial_started_at) OR
        (trial_started_at IS NULL AND trial_ends_at IS NULL)
    ),
    CONSTRAINT check_company_saas_subscription_billing_dates CHECK (
        (current_billing_period_starts_at IS NOT NULL AND current_billing_period_ends_at IS NOT NULL AND current_billing_period_ends_at > current_billing_period_starts_at) OR
        (current_billing_period_starts_at IS NULL AND current_billing_period_ends_at IS NULL)
    ),
    CONSTRAINT check_company_saas_subscription_cancellation_dates CHECK (
        (cancellation_requested_at IS NOT NULL AND cancellation_effective_at IS NOT NULL AND cancellation_effective_at >= cancellation_requested_at) OR
        (cancellation_requested_at IS NULL AND cancellation_effective_at IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_company_saas_subscriptions_company_id ON public.company_saas_subscriptions(company_id);
CREATE INDEX IF NOT EXISTS idx_company_saas_subscriptions_saas_plan_id ON public.company_saas_subscriptions(saas_plan_id);
CREATE INDEX IF NOT EXISTS idx_company_saas_subscriptions_status ON public.company_saas_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_company_saas_subscriptions_trial_ends_at ON public.company_saas_subscriptions(trial_ends_at);
CREATE INDEX IF NOT EXISTS idx_company_saas_subscriptions_next_billing_date ON public.company_saas_subscriptions(next_billing_date);

CREATE OR REPLACE TRIGGER set_public_company_saas_subscriptions_updated_at
    BEFORE UPDATE ON public.company_saas_subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updatedAt();

COMMENT ON TABLE public.company_saas_subscriptions IS 'Tracks the active SaaS plan, trial status, and billing cycle for each tenant company using the Hyper M v2 platform.';
COMMENT ON COLUMN public.company_saas_subscriptions.company_id IS 'The tenant company this subscription belongs to. Unique, as a company has only one active subscription record.';
COMMENT ON COLUMN public.company_saas_subscriptions.saas_plan_id IS 'The SaaS plan the company is currently subscribed to or trialing.';
COMMENT ON COLUMN public.company_saas_subscriptions.status IS 'Current status of the company''s subscription (e.g., trialing, active, past_due).';
COMMENT ON COLUMN public.company_saas_subscriptions.trial_started_at IS 'Timestamp when the trial period for the current (or initial) plan started.';
COMMENT ON COLUMN public.company_saas_subscriptions.trial_ends_at IS 'Timestamp when the trial period ends or ended.';
COMMENT ON COLUMN public.company_saas_subscriptions.current_billing_period_starts_at IS 'Start date/time of the current paid billing cycle.';
COMMENT ON COLUMN public.company_saas_subscriptions.current_billing_period_ends_at IS 'End date/time of the current paid billing cycle.';
COMMENT ON COLUMN public.company_saas_subscriptions.next_billing_date IS 'Date when the next renewal payment is due. Drives renewal/invoicing logic.';
COMMENT ON COLUMN public.company_saas_subscriptions.last_payment_attempted_at IS 'Timestamp of the most recent payment attempt for this subscription.';
COMMENT ON COLUMN public.company_saas_subscriptions.last_payment_succeeded_at IS 'Timestamp of the most recent successful payment.';
COMMENT ON COLUMN public.company_saas_subscriptions.last_payment_failed_reason IS 'Reason if the last payment attempt failed (e.g., from payment gateway).';
COMMENT ON COLUMN public.company_saas_subscriptions.cancellation_requested_at IS 'Timestamp when the company admin requested to cancel their subscription.';
COMMENT ON COLUMN public.company_saas_subscriptions.cancellation_effective_at IS 'Timestamp when the cancellation will take effect (typically end of the current paid period).';
COMMENT ON COLUMN public.company_saas_subscriptions.cancellation_reason IS 'Reason provided for cancellation (if any).';
COMMENT ON COLUMN public.company_saas_subscriptions.metadata IS 'JSONB field for storing external references like payment gateway subscription IDs or other relevant structured data.';