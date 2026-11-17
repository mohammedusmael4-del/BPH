-- BPH-HMIS Core Database Schema v1.0
-- PostgreSQL 15+
-- Scope: facility/department configuration, access-control reference data,
-- patient identity, encounters, core clinical documentation, and audit events.
-- Authentication credentials should be managed by Django's authentication framework;
-- this schema's app_user table is the application profile linked to Django's user ID.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE facility (
    facility_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    facility_code VARCHAR(30) NOT NULL UNIQUE,
    facility_name VARCHAR(200) NOT NULL,
    facility_type VARCHAR(40) NOT NULL DEFAULT 'primary_hospital',
    region VARCHAR(100), zone VARCHAR(100), woreda VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE department (
    department_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    facility_id UUID NOT NULL REFERENCES facility(facility_id),
    department_code VARCHAR(30) NOT NULL,
    department_name VARCHAR(150) NOT NULL,
    department_type VARCHAR(50) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (facility_id, department_code),
    UNIQUE (facility_id, department_name)
);

CREATE TABLE service_point (
    service_point_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id UUID NOT NULL REFERENCES department(department_id),
    service_point_code VARCHAR(30) NOT NULL,
    service_point_name VARCHAR(150) NOT NULL,
    service_type VARCHAR(50) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (department_id, service_point_code)
);

-- Link this profile to the Django AUTH_USER_MODEL primary key.
-- Do not store passwords in this table.
CREATE TABLE app_user (
    user_id UUID PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facility(facility_id),
    department_id UUID REFERENCES department(department_id),
    username_display VARCHAR(150) NOT NULL,
    full_name VARCHAR(200) NOT NULL,
    professional_category VARCHAR(80),
    license_number VARCHAR(80),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE app_role (
    role_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_code VARCHAR(50) NOT NULL UNIQUE,
    role_name VARCHAR(100) NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE app_permission (
    permission_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    permission_code VARCHAR(100) NOT NULL UNIQUE,
    permission_name VARCHAR(150) NOT NULL,
    description TEXT
);

CREATE TABLE user_role (
    user_id UUID NOT NULL REFERENCES app_user(user_id),
    role_id UUID NOT NULL REFERENCES app_role(role_id),
    facility_id UUID NOT NULL REFERENCES facility(facility_id),
    assigned_by UUID REFERENCES app_user(user_id),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, role_id, facility_id),
    CHECK (expires_at IS NULL OR expires_at > assigned_at)
);

CREATE TABLE role_permission (
    role_id UUID NOT NULL REFERENCES app_role(role_id),
    permission_id UUID NOT NULL REFERENCES app_permission(permission_id),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE patient (
    patient_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    facility_id UUID NOT NULL REFERENCES facility(facility_id),
    mrn VARCHAR(30) NOT NULL,
    given_name VARCHAR(100) NOT NULL,
    father_name VARCHAR(100),
    grandfather_name VARCHAR(100),
    other_names VARCHAR(200),
    sex_at_registration VARCHAR(20) NOT NULL CHECK (sex_at_registration IN ('female','male','intersex','unknown')),
    date_of_birth DATE,
    date_of_birth_estimated BOOLEAN NOT NULL DEFAULT FALSE,
    phone_number VARCHAR(30),
    preferred_language VARCHAR(30),
    marital_status VARCHAR(30),
    registration_status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (registration_status IN ('active','merged','inactive')),
    merged_into_patient_id UUID REFERENCES patient(patient_id),
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    registered_by UUID REFERENCES app_user(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (facility_id, mrn),
    CHECK ((registration_status = 'merged' AND merged_into_patient_id IS NOT NULL) OR
           (registration_status <> 'merged' AND merged_into_patient_id IS NULL)),
    CHECK (merged_into_patient_id IS NULL OR merged_into_patient_id <> patient_id)
);

CREATE TABLE patient_identifier (
    patient_identifier_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES patient(patient_id),
    identifier_type VARCHAR(50) NOT NULL,
    identifier_value VARCHAR(150) NOT NULL,
    issuing_authority VARCHAR(150),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    recorded_by UUID REFERENCES app_user(user_id),
    UNIQUE (patient_id, identifier_type, identifier_value)
);

CREATE TABLE patient_contact (
    patient_contact_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES patient(patient_id),
    contact_name VARCHAR(200) NOT NULL,
    relationship VARCHAR(60),
    phone_number VARCHAR(30),
    is_emergency_contact BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE patient_address (
    patient_address_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES patient(patient_id),
    region VARCHAR(100), zone VARCHAR(100), woreda VARCHAR(100),
    kebele VARCHAR(100), house_or_locality VARCHAR(200),
    is_current BOOLEAN NOT NULL DEFAULT TRUE,
    valid_from DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_to DATE,
    CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE encounter (
    encounter_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    facility_id UUID NOT NULL REFERENCES facility(facility_id),
    patient_id UUID NOT NULL REFERENCES patient(patient_id),
    encounter_number VARCHAR(40) NOT NULL,
    encounter_type VARCHAR(30) NOT NULL CHECK (encounter_type IN ('OPD','EMERGENCY','IPD','MATERNITY','PROCEDURE','OTHER')),
    department_id UUID NOT NULL REFERENCES department(department_id),
    service_point_id UUID REFERENCES service_point(service_point_id),
    attending_user_id UUID REFERENCES app_user(user_id),
    arrival_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','completed','cancelled')),
    chief_complaint TEXT,
    source_of_referral VARCHAR(100),
    created_by UUID REFERENCES app_user(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (facility_id, encounter_number),
    CHECK (ended_at IS NULL OR ended_at >= arrival_at)
);

CREATE TABLE encounter_status_history (
    history_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    encounter_id UUID NOT NULL REFERENCES encounter(encounter_id),
    previous_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,
    changed_by UUID REFERENCES app_user(user_id),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reason TEXT
);

CREATE TABLE clinical_note (
    clinical_note_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    encounter_id UUID NOT NULL REFERENCES encounter(encounter_id),
    note_type VARCHAR(40) NOT NULL,
    note_text TEXT NOT NULL,
    author_user_id UUID NOT NULL REFERENCES app_user(user_id),
    authored_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finalized_at TIMESTAMPTZ,
    finalized_by UUID REFERENCES app_user(user_id),
    amendment_of_note_id UUID REFERENCES clinical_note(clinical_note_id),
    amendment_reason TEXT,
    is_void BOOLEAN NOT NULL DEFAULT FALSE,
    CHECK ((finalized_at IS NULL AND finalized_by IS NULL) OR
           (finalized_at IS NOT NULL AND finalized_by IS NOT NULL)),
    CHECK (amendment_of_note_id IS NULL OR amendment_reason IS NOT NULL)
);

CREATE TABLE vital_sign (
    vital_sign_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    encounter_id UUID NOT NULL REFERENCES encounter(encounter_id),
    measured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    temperature_c NUMERIC(4,1),
    pulse_bpm SMALLINT,
    respiratory_rate_per_min SMALLINT,
    systolic_bp_mm_hg SMALLINT,
    diastolic_bp_mm_hg SMALLINT,
    spo2_percent NUMERIC(5,2),
    weight_kg NUMERIC(6,2),
    height_cm NUMERIC(6,2),
    muac_cm NUMERIC(5,2),
    pain_score SMALLINT CHECK (pain_score BETWEEN 0 AND 10),
    consciousness_level VARCHAR(40),
    recorded_by UUID REFERENCES app_user(user_id),
    CHECK (temperature_c IS NULL OR temperature_c BETWEEN 20 AND 50),
    CHECK (spo2_percent IS NULL OR spo2_percent BETWEEN 0 AND 100),
    CHECK (pulse_bpm IS NULL OR pulse_bpm BETWEEN 0 AND 300),
    CHECK (respiratory_rate_per_min IS NULL OR respiratory_rate_per_min BETWEEN 0 AND 100)
);

CREATE TABLE diagnosis (
    diagnosis_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    encounter_id UUID NOT NULL REFERENCES encounter(encounter_id),
    coding_system VARCHAR(30),
    diagnosis_code VARCHAR(30),
    diagnosis_text VARCHAR(500) NOT NULL,
    diagnosis_type VARCHAR(20) NOT NULL CHECK (diagnosis_type IN ('primary','secondary','differential','complication')),
    clinical_status VARCHAR(20) NOT NULL DEFAULT 'active',
    diagnosed_by UUID REFERENCES app_user(user_id),
    diagnosed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_event (
    audit_event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    facility_id UUID REFERENCES facility(facility_id),
    actor_user_id UUID REFERENCES app_user(user_id),
    event_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    action VARCHAR(60) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID,
    reason TEXT,
    request_id VARCHAR(100),
    source_ip INET,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX idx_patient_name ON patient (facility_id, lower(given_name), lower(father_name));
CREATE INDEX idx_patient_phone ON patient (facility_id, phone_number);
CREATE INDEX idx_patient_registered_at ON patient (facility_id, registered_at DESC);
CREATE INDEX idx_encounter_patient_date ON encounter (patient_id, arrival_at DESC);
CREATE INDEX idx_encounter_department_status ON encounter (department_id, status, arrival_at DESC);
CREATE INDEX idx_encounter_attending ON encounter (attending_user_id, arrival_at DESC);
CREATE INDEX idx_vital_encounter_date ON vital_sign (encounter_id, measured_at DESC);
CREATE INDEX idx_diagnosis_encounter ON diagnosis (encounter_id);
CREATE INDEX idx_audit_entity_date ON audit_event (entity_type, entity_id, event_at DESC);
CREATE INDEX idx_audit_actor_date ON audit_event (actor_user_id, event_at DESC);
CREATE INDEX idx_patient_identifier_lookup ON patient_identifier (identifier_type, identifier_value);

-- updated_at trigger function for mutable master/transaction tables.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_facility_updated_at BEFORE UPDATE ON facility
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_department_updated_at BEFORE UPDATE ON department
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_app_user_updated_at BEFORE UPDATE ON app_user
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_patient_updated_at BEFORE UPDATE ON patient
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_encounter_updated_at BEFORE UPDATE ON encounter
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Seed the initial BPH facility record. Department and user records are added
-- after institutional codes, names, and account governance are confirmed.
INSERT INTO facility (facility_code, facility_name, facility_type, region, zone, woreda)
VALUES ('BPH', 'Badessa Primary Hospital', 'primary_hospital', 'Oromia', 'West Hararghe', 'Badessa')
ON CONFLICT (facility_code) DO NOTHING;

COMMIT;
