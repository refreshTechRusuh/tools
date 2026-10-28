-- ============================================================
-- Rusuh Booking Tiket — Combined DB Init Script
-- Dijalankan otomatis oleh Docker postgres container saat pertama kali.
-- Urutan: event-service tables dulu, lalu booking-service, lalu payment-service.
-- ============================================================

-- ---- event-service ------------------------------------------------
CREATE TABLE IF NOT EXISTS event (
    id            UUID PRIMARY KEY,
    name          TEXT NOT NULL,
    sale_opens_at TIMESTAMPTZ,
    status        TEXT NOT NULL DEFAULT 'draft',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT event_status_check CHECK (status IN ('draft','on_sale','sold_out','closed'))
);

CREATE TABLE IF NOT EXISTS ticket_category (
    id         UUID PRIMARY KEY,
    event_id   UUID NOT NULL REFERENCES event(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    price      BIGINT NOT NULL,
    capacity   INT NOT NULL,
    available  INT NOT NULL CHECK (available >= 0),
    CONSTRAINT tc_available_lte_capacity CHECK (available <= capacity)
);

CREATE INDEX IF NOT EXISTS idx_event_status ON event(status);
CREATE INDEX IF NOT EXISTS idx_tc_event_id ON ticket_category(event_id);

-- ---- booking-service -----------------------------------------------
CREATE TABLE IF NOT EXISTS booking (
    id                  UUID PRIMARY KEY,
    user_id             UUID,                          -- NULL untuk guest
    event_id            UUID NOT NULL REFERENCES event(id),
    email               TEXT NOT NULL,
    status              TEXT NOT NULL DEFAULT 'HELD',
    booking_expires_at  TIMESTAMPTZ,
    payment_expires_at  TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT booking_status_check CHECK (status IN ('HELD','PAID','EXPIRED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS booking_item (
    id              UUID PRIMARY KEY,
    booking_id      UUID NOT NULL REFERENCES booking(id) ON DELETE CASCADE,
    category_id     UUID NOT NULL REFERENCES ticket_category(id),
    nik             CHAR(16) NOT NULL,
    price_snapshot  BIGINT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_booking_event_status   ON booking(event_id, status);
CREATE INDEX IF NOT EXISTS idx_booking_item_nik        ON booking_item(nik);
CREATE INDEX IF NOT EXISTS idx_booking_payment_expires ON booking(payment_expires_at) WHERE status = 'HELD';

-- ---- dukcapil-mock (BE-1) ------------------------------------------
-- Data kependudukan tiruan. verify mencocokkan {nik,nama,tgl_lahir,nama_ibu}.
CREATE TABLE IF NOT EXISTS residents (
    nik        CHAR(16) PRIMARY KEY,
    nama       TEXT NOT NULL,
    tgl_lahir  DATE NOT NULL,
    nama_ibu   TEXT NOT NULL
);

INSERT INTO residents (nik, nama, tgl_lahir, nama_ibu) VALUES
    ('3273000000000001', 'Budi Santoso',  '1990-01-01', 'Siti Aminah'),
    ('3273000000000002', 'Ani Lestari',   '1992-05-17', 'Rina Marlina'),
    ('3273000000000003', 'Candra Wijaya', '1988-11-30', 'Dewi Kartika'),
    ('3273000000000004', 'Dedi Pratama',  '1995-07-09', 'Eka Yuliana'),
    ('3273000000000005', 'Eka Putri',     '2000-03-25', 'Fitri Handayani')
ON CONFLICT (nik) DO NOTHING;

-- ---- user-service (BE-1) -------------------------------------------
-- Akun login. id = UUID (di-generate aplikasi). email UNIK. role customer|admin.
CREATE TABLE IF NOT EXISTS app_user (
    id            UUID PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'customer',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT app_user_role_check CHECK (role IN ('customer','admin'))
);

CREATE INDEX IF NOT EXISTS idx_app_user_email ON app_user(email);

-- ---- payment-service -----------------------------------------------
CREATE TABLE IF NOT EXISTS payment (
    id           UUID PRIMARY KEY,
    booking_id   UUID NOT NULL REFERENCES booking(id),
    method       TEXT,
    status       TEXT NOT NULL DEFAULT 'PENDING',
    provider_ref TEXT,
    snap_token   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT payment_status_check CHECK (status IN ('PENDING','SUCCESS','FAILED','EXPIRED'))
);

CREATE TABLE IF NOT EXISTS payment_callback_log (
    idempotency_key TEXT PRIMARY KEY,
    booking_id      UUID,
    result          TEXT,
    processed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_booking_id ON payment(booking_id);

-- ---- seed data (dev only) ------------------------------------------
-- Satu event contoh agar service bisa langsung dicoba tanpa admin CRUD dulu.
INSERT INTO event (id, name, sale_opens_at, status, created_at)
VALUES
    ('018f2c1a-0000-7000-8000-0000000000a1', 'Coldplay: Music of the Spheres 2026',
     '2026-11-01T10:00:00+07:00', 'on_sale', NOW()),
    ('018f2c1a-0000-7000-8000-0000000000a2', 'Tomorrowland Jakarta 2026',
     '2026-12-01T10:00:00+07:00', 'draft', NOW())
ON CONFLICT DO NOTHING;

INSERT INTO ticket_category (id, event_id, name, price, capacity, available)
VALUES
    ('cat-vip-001', '018f2c1a-0000-7000-8000-0000000000a1', 'VIP Ultimate Experience', 5000000, 100, 100),
    ('cat-reg-001', '018f2c1a-0000-7000-8000-0000000000a1', 'Reguler',                  500000, 500, 500),
    ('cat-vip-002', '018f2c1a-0000-7000-8000-0000000000a2', 'VVIP',                    7500000,  50,  50)
ON CONFLICT DO NOTHING;
