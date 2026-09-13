-- AI Video Platform — PostgreSQL 16
-- Phase 1 system of record. Apply with a migrator (Alembic), not by hand in prod.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

CREATE TYPE auth_provider AS ENUM ('phone', 'email', 'google');
CREATE TYPE user_role AS ENUM ('user', 'editor', 'admin');
CREATE TYPE template_tier AS ENUM ('free', 'premium');
CREATE TYPE media_kind AS ENUM ('image', 'video', 'audio', 'other');
CREATE TYPE upload_status AS ENUM ('pending', 'ready', 'rejected', 'deleted');
CREATE TYPE slot_type AS ENUM ('image', 'video', 'text', 'audio');
CREATE TYPE job_status AS ENUM (
  'queued',
  'processing',
  'uploading',
  'completed',
  'failed',
  'canceled'
);
CREATE TYPE job_priority AS ENUM ('free', 'premium');
CREATE TYPE payment_status AS ENUM (
  'created',
  'pending',
  'paid',
  'failed',
  'refunded'
);
CREATE TYPE subscription_status AS ENUM (
  'active',
  'past_due',
  'canceled',
  'expired'
);
CREATE TYPE order_status AS ENUM (
  'draft',
  'awaiting_payment',
  'paid',
  'assigned',
  'in_progress',
  'delivered',
  'revision',
  'closed',
  'canceled'
);
CREATE TYPE booking_status AS ENUM (
  'inquiry',
  'quoted',
  'confirmed',
  'shot',
  'delivered',
  'canceled'
);
CREATE TYPE notification_channel AS ENUM ('in_app', 'push', 'sms', 'whatsapp');

-- ---------------------------------------------------------------------------
-- Updated-at trigger
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------

CREATE TABLE users (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role            user_role NOT NULL DEFAULT 'user',
  display_name    text,
  locale          text NOT NULL DEFAULT 'en-IN',
  region_state    text,
  avatar_file_id  uuid,
  is_blocked      boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE auth_identities (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  provider        auth_provider NOT NULL,
  subject         citext NOT NULL,
  verified_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, subject)
);

CREATE INDEX auth_identities_user_idx ON auth_identities (user_id);

CREATE TABLE otp_challenges (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone           text NOT NULL,
  code_hash       text NOT NULL,
  attempts        integer NOT NULL DEFAULT 0,
  max_attempts    integer NOT NULL DEFAULT 5,
  expires_at      timestamptz NOT NULL,
  consumed_at     timestamptz,
  ip_hash         text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX otp_phone_created_idx ON otp_challenges (phone, created_at DESC);

CREATE TABLE sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  refresh_hash    text NOT NULL,
  user_agent      text,
  ip_hash         text,
  expires_at      timestamptz NOT NULL,
  revoked_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX sessions_user_idx ON sessions (user_id) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- Catalog
-- ---------------------------------------------------------------------------

CREATE TABLE categories (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug            text NOT NULL UNIQUE,
  name            jsonb NOT NULL,
  sort_order      integer NOT NULL DEFAULT 0,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE music_tracks (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title           text NOT NULL,
  language        text,
  mood            text,
  duration_sec    integer NOT NULL CHECK (duration_sec > 0),
  s3_key          text NOT NULL,
  license_ref     text,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE templates (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id     uuid NOT NULL REFERENCES categories (id),
  slug            text NOT NULL UNIQUE,
  name            text NOT NULL,
  description     text,
  tier            template_tier NOT NULL DEFAULT 'free',
  duration_sec    integer NOT NULL CHECK (duration_sec BETWEEN 5 AND 90),
  width           integer NOT NULL CHECK (width > 0),
  height          integer NOT NULL CHECK (height > 0),
  fps             integer NOT NULL DEFAULT 30,
  preview_key     text NOT NULL,
  thumbnail_key   text NOT NULL,
  default_music_id uuid REFERENCES music_tracks (id),
  composition_id  text NOT NULL,
  renderer        text NOT NULL DEFAULT 'remotion' CHECK (renderer IN ('remotion', 'ffmpeg')),
  is_published    boolean NOT NULL DEFAULT false,
  published_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX templates_category_pub_idx
  ON templates (category_id, is_published, created_at DESC);

CREATE TABLE template_configs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id     uuid NOT NULL REFERENCES templates (id) ON DELETE CASCADE,
  version         integer NOT NULL,
  schema_version  integer NOT NULL DEFAULT 1,
  config          jsonb NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (template_id, version)
);

CREATE TABLE devotional_days (
  weekday         integer PRIMARY KEY CHECK (weekday BETWEEN 0 AND 6),
  deity_key       text NOT NULL,
  default_template_id uuid REFERENCES templates (id),
  mantra_track_id uuid REFERENCES music_tracks (id)
);

-- ---------------------------------------------------------------------------
-- User media + projects
-- ---------------------------------------------------------------------------

CREATE TABLE uploaded_files (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id),
  kind            media_kind NOT NULL,
  status          upload_status NOT NULL DEFAULT 'pending',
  original_name   text,
  content_type    text NOT NULL,
  byte_size       bigint NOT NULL CHECK (byte_size > 0),
  checksum_sha256 text,
  s3_key          text NOT NULL UNIQUE,
  width           integer,
  height          integer,
  duration_ms     integer,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX uploaded_files_user_idx ON uploaded_files (user_id, created_at DESC);

ALTER TABLE users
  ADD CONSTRAINT users_avatar_fk
  FOREIGN KEY (avatar_file_id) REFERENCES uploaded_files (id);

CREATE TABLE projects (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id),
  template_id     uuid NOT NULL REFERENCES templates (id),
  config_version  integer NOT NULL,
  title           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE INDEX projects_user_idx ON projects (user_id, created_at DESC);

CREATE TABLE project_slots (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id      uuid NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  slot_id         text NOT NULL,
  slot_type       slot_type NOT NULL,
  file_id         uuid REFERENCES uploaded_files (id) ON DELETE SET NULL,
  text_value      text,
  music_track_id  uuid REFERENCES music_tracks (id),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (project_id, slot_id)
);

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

CREATE TABLE rendering_jobs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id      uuid NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES users (id),
  status          job_status NOT NULL DEFAULT 'queued',
  priority        job_priority NOT NULL DEFAULT 'free',
  idempotency_key text NOT NULL,
  progress_pct    integer NOT NULL DEFAULT 0 CHECK (progress_pct BETWEEN 0 AND 100),
  output_key      text,
  output_width    integer,
  output_height   integer,
  has_watermark   boolean NOT NULL DEFAULT true,
  error_code      text,
  error_detail    text,
  queued_at       timestamptz NOT NULL DEFAULT now(),
  started_at      timestamptz,
  finished_at     timestamptz,
  UNIQUE (project_id, idempotency_key)
);

CREATE INDEX jobs_status_priority_idx
  ON rendering_jobs (status, priority, queued_at);
CREATE INDEX jobs_user_idx ON rendering_jobs (user_id, queued_at DESC);

CREATE TABLE rendering_job_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id          uuid NOT NULL REFERENCES rendering_jobs (id) ON DELETE CASCADE,
  status          job_status NOT NULL,
  message         text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Billing
-- ---------------------------------------------------------------------------

CREATE TABLE plans (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code            text NOT NULL UNIQUE,
  name            text NOT NULL,
  price_paise     integer NOT NULL CHECK (price_paise >= 0),
  currency        text NOT NULL DEFAULT 'INR',
  weekly_renders  integer,
  monthly_renders integer,
  max_height      integer NOT NULL DEFAULT 720,
  watermark       boolean NOT NULL DEFAULT true,
  priority        job_priority NOT NULL DEFAULT 'free',
  is_active       boolean NOT NULL DEFAULT true
);

CREATE TABLE subscriptions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id),
  plan_id         uuid NOT NULL REFERENCES plans (id),
  status          subscription_status NOT NULL,
  current_period_end timestamptz,
  razorpay_sub_id text UNIQUE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX subscriptions_one_active
  ON subscriptions (user_id)
  WHERE status = 'active';

CREATE TABLE payments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id),
  subscription_id uuid REFERENCES subscriptions (id),
  custom_order_id uuid,
  amount_paise    integer NOT NULL CHECK (amount_paise > 0),
  currency        text NOT NULL DEFAULT 'INR',
  status          payment_status NOT NULL DEFAULT 'created',
  razorpay_order_id text UNIQUE,
  razorpay_payment_id text UNIQUE,
  raw_webhook     jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Human editing (Service 2)
-- ---------------------------------------------------------------------------

CREATE TABLE editors (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid REFERENCES users (id),
  display_name    text NOT NULL,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE custom_orders (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id),
  editor_id       uuid REFERENCES editors (id) ON DELETE SET NULL,
  occasion        text,
  description     text NOT NULL,
  reference_url   text,
  due_on          date,
  status          order_status NOT NULL DEFAULT 'draft',
  price_paise     integer,
  final_file_id   uuid REFERENCES uploaded_files (id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE custom_order_files (
  order_id        uuid NOT NULL REFERENCES custom_orders (id) ON DELETE CASCADE,
  file_id         uuid NOT NULL REFERENCES uploaded_files (id),
  PRIMARY KEY (order_id, file_id)
);

ALTER TABLE payments
  ADD CONSTRAINT payments_custom_order_fk
  FOREIGN KEY (custom_order_id) REFERENCES custom_orders (id);

-- ---------------------------------------------------------------------------
-- Photography booking (Service 3 — schema ready, product later)
-- ---------------------------------------------------------------------------

CREATE TABLE bookings (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id),
  occasion        text NOT NULL,
  city            text NOT NULL,
  event_on        date,
  notes           text,
  status          booking_status NOT NULL DEFAULT 'inquiry',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Notifications + audit
-- ---------------------------------------------------------------------------

CREATE TABLE notifications (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  channel         notification_channel NOT NULL DEFAULT 'in_app',
  title           text NOT NULL,
  body            text NOT NULL,
  payload         jsonb,
  read_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX notifications_user_unread_idx
  ON notifications (user_id, created_at DESC)
  WHERE read_at IS NULL;

CREATE TABLE audit_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id        uuid REFERENCES users (id),
  action          text NOT NULL,
  entity_type     text NOT NULL,
  entity_id       uuid,
  meta            jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_logs_entity_idx ON audit_logs (entity_type, entity_id);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

CREATE TRIGGER users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER templates_updated_at BEFORE UPDATE ON templates
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER projects_updated_at BEFORE UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER subscriptions_updated_at BEFORE UPDATE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER payments_updated_at BEFORE UPDATE ON payments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER custom_orders_updated_at BEFORE UPDATE ON custom_orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER bookings_updated_at BEFORE UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Seed plans
-- ---------------------------------------------------------------------------

INSERT INTO plans (code, name, price_paise, weekly_renders, monthly_renders, max_height, watermark, priority)
VALUES
  ('free', 'Free', 0, 3, NULL, 720, true, 'free'),
  ('premium_in', 'Premium', 14900, NULL, 60, 1080, false, 'premium');
