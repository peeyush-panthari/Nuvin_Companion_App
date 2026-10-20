-- Nuvin Master Production Schema (PostgreSQL + pgvector)
CREATE EXTENSION IF NOT EXISTS vector;

-- 1. USERS & COMPANION PROFILES
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    phone_e164 TEXT UNIQUE NOT NULL,
    display_name TEXT,
    persona TEXT NOT NULL CHECK (persona IN ('elder', 'ear')),
    age_band TEXT NOT NULL CHECK (age_band IN ('18-34', '35-54', '55-64', '65-74', '75+')),
    gender TEXT CHECK (gender IN ('female', 'male', 'other', 'unspecified')),
    companion_name TEXT NOT NULL DEFAULT 'Nuvin',
    companion_gender TEXT NOT NULL DEFAULT 'female' CHECK (companion_gender IN ('female', 'male')),
    preferred_tone TEXT NOT NULL DEFAULT 'respectful' CHECK (preferred_tone IN ('respectful', 'friendly')),
    locale TEXT NOT NULL DEFAULT 'en-IN',
    timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata',
    region TEXT NOT NULL DEFAULT 'IN-DL',
    accessibility JSONB NOT NULL DEFAULT '{"font_scale": 1.3, "high_contrast": false}'::jsonb,
    voice_pref JSONB NOT NULL DEFAULT '{"rate": 0.85, "pause_tolerance_ms": 3500, "repeat_on_confusion": true}'::jsonb,
    quiet_hours JSONB NOT NULL DEFAULT '{"start": "22:00", "end": "07:00"}'::jsonb,
    wake_word_phrase TEXT NOT NULL DEFAULT 'Hey Nuvin',
    custom_wake_word_enrolled BOOLEAN NOT NULL DEFAULT false,
    duress_pin_hash TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. CONTACTS (Emergency & Trusted Circle)
CREATE TABLE IF NOT EXISTS contacts (
    id UUID PRIMARY KEY,
    owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    linked_user_id UUID REFERENCES users(id),
    display_name TEXT NOT NULL,
    spoken_disambiguation TEXT NOT NULL,
    relationship TEXT,
    kind TEXT NOT NULL CHECK (kind IN ('emergency', 'companion', 'trusted_circle', 'friend')),
    priority SMALLINT CHECK (priority BETWEEN 1 AND 5),
    muted BOOLEAN NOT NULL DEFAULT false,
    blocked BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. CONTACT CHANNELS (Phone, WhatsApp, SMS)
CREATE TABLE IF NOT EXISTS contact_channels (
    id UUID PRIMARY KEY,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('sms', 'whatsapp', 'call', 'push', 'email')),
    address_enc BYTEA NOT NULL,
    verification_status TEXT NOT NULL CHECK (verification_status IN ('unverified', 'verified', 'stale', 'failed')),
    verified_at TIMESTAMPTZ,
    last_delivery_ok_at TIMESTAMPTZ,
    preference_rank SMALLINT NOT NULL DEFAULT 1
);

-- 4. REMINDERS (Offline-First Sync Engine)
CREATE TABLE IF NOT EXISTS reminders (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('medicine', 'appointment', 'date', 'routine', 'habit', 'bill', 'other')),
    title TEXT NOT NULL,
    details_enc BYTEA,
    schedule TEXT NOT NULL, -- Cron expression or ISO date for one-off
    is_recurring BOOLEAN NOT NULL DEFAULT true,
    timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata',
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'completed', 'cancelled')),
    version INT NOT NULL DEFAULT 1,
    next_fire_at TIMESTAMPTZ,
    source TEXT NOT NULL CHECK (source IN ('voice', 'ui', 'caregiver', 'vault')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. REMINDER OCCURRENCES
CREATE TABLE IF NOT EXISTS reminder_occurrences (
    id UUID PRIMARY KEY,
    reminder_id UUID NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
    reminder_version INT NOT NULL,
    due_at TIMESTAMPTZ NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('scheduled', 'delivered', 'acknowledged', 'completed', 'snoozed', 'skipped', 'needs_help', 'missed', 'escalated')),
    delivered_at TIMESTAMPTZ,
    delivery_origin TEXT CHECK (delivery_origin IN ('local_device', 'cloud_push', 'cloud_call')),
    response_type TEXT CHECK (response_type IN ('taken', 'snooze', 'skip', 'help', 'silence')),
    response_at TIMESTAMPTZ,
    idempotency_key TEXT UNIQUE NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_occ_due_state ON reminder_occurrences (due_at, state);

-- 6. LONGITUDINAL MEMORY & LIFE THREADS
CREATE TABLE IF NOT EXISTS life_threads (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category TEXT NOT NULL CHECK (category IN ('career', 'relationship', 'grief', 'caregiving', 'health_routine', 'family', 'goal', 'preference', 'other')),
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    entities JSONB NOT NULL DEFAULT '[]'::jsonb,
    sensitivity SMALLINT NOT NULL DEFAULT 2 CHECK (sensitivity BETWEEN 1 AND 5),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'resolved', 'archived')),
    embedding VECTOR(1024),
    last_discussed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

-- 7. INDIVIDUAL MEMORY ITEMS (For granular inspection & user edit/forget)
CREATE TABLE IF NOT EXISTS memory_items (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    thread_id UUID REFERENCES life_threads(id),
    category TEXT NOT NULL CHECK (category IN ('fact', 'preference', 'routine', 'health', 'person', 'story')),
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    sensitivity SMALLINT NOT NULL DEFAULT 2,
    source_type TEXT NOT NULL CHECK (source_type IN ('conversation', 'user_edit', 'onboarding')),
    confidence REAL NOT NULL DEFAULT 1.0,
    user_confirmed BOOLEAN NOT NULL DEFAULT false,
    embedding VECTOR(1024),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_memory_user_active ON memory_items (user_id) WHERE deleted_at IS NULL;

-- 8. CONVERSATION SUMMARIES
CREATE TABLE IF NOT EXISTS conversation_summaries (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL UNIQUE,
    summary TEXT NOT NULL,
    topics TEXT[] NOT NULL DEFAULT '{}',
    mood_detected TEXT,
    safety_tags TEXT[] NOT NULL DEFAULT '{}',
    turn_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 9. DETERMINISTIC SOS INCIDENTS & 8-HOUR LIVE TRACKING
CREATE TABLE IF NOT EXISTS sos_incidents (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    trigger_type TEXT NOT NULL CHECK (trigger_type IN ('button_hold', 'voice_keyword', 'manual')),
    severity SMALLINT NOT NULL DEFAULT 3,
    state TEXT NOT NULL CHECK (state IN ('open', 'notifying', 'acknowledged', 'resolved', 'cancelled')),
    initial_latitude DOUBLE PRECISION,
    initial_longitude DOUBLE PRECISION,
    live_tracking_token TEXT UNIQUE NOT NULL,
    tracking_expires_at TIMESTAMPTZ NOT NULL,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at TIMESTAMPTZ,
    close_reason TEXT
);

-- 10. SOS LIVE LOCATION PINGS (8-Hour Ephemeral Log)
CREATE TABLE IF NOT EXISTS sos_location_pings (
    id UUID PRIMARY KEY,
    incident_id UUID NOT NULL REFERENCES sos_incidents(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy_meters REAL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pings_incident ON sos_location_pings (incident_id, recorded_at DESC);

-- 11. TRUST PLANE: SAFETY EVENTS LOG
CREATE TABLE IF NOT EXISTS safety_events (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    session_id UUID,
    category TEXT NOT NULL CHECK (category IN ('explicit_content', 'self_harm', 'harm_to_others', 'illegal_activity', 'financial_scam', 'medical_boundary', 'other')),
    tier SMALLINT NOT NULL CHECK (tier BETWEEN 0 AND 3),
    score REAL NOT NULL,
    flagged_text_snippet TEXT,
    action_taken TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 12. TRUST PLANE: IMMUTABLE AUDIT EVENTS (WORM)
CREATE TABLE IF NOT EXISTS audit_events (
    id UUID PRIMARY KEY,
    actor_type TEXT NOT NULL CHECK (actor_type IN ('user', 'contact', 'system', 'agent')),
    actor_id UUID,
    subject_user_id UUID NOT NULL,
    action TEXT NOT NULL,
    resource TEXT NOT NULL,
    resource_id UUID,
    purpose TEXT NOT NULL,
    result TEXT NOT NULL CHECK (result IN ('allowed', 'denied', 'executed', 'failed')),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    at TIMESTAMPTZ NOT NULL DEFAULT now(),
    trace_id TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_subject_at ON audit_events (subject_user_id, at DESC);
