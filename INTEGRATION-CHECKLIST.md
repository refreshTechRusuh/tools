# Checklist Integrasi BE-1 → BE-2

Dokumen ini mencatat **semua titik yang saat ini di-mock** dari BE-1 (Queue Service)
dan langkah yang harus dilakukan saat BE-1 sudah selesai dan siap diintegrasikan.

Cari semua titik di codebase dengan: `grep -rn "TODO(BE-1" --include="*.go"`

---

## 1. ACCESS_TOKEN_SECRET — Shared JWT Secret

**Status saat ini:** mock dengan `dev-secret-change-in-production`

**File yang perlu diubah:**
- `booking-service/.env`  → `ACCESS_TOKEN_SECRET=<secret dari BE-1>`
- `event-service/.env`    → `ACCESS_TOKEN_SECRET=<secret dari BE-1>`
- `payment-service/.env`  → `ACCESS_TOKEN_SECRET=<secret dari BE-1>`

**Cara dapat nilai dari BE-1:**
- Minta tim BE-1 nilai `ACCESS_TOKEN_SECRET` yang dipakai Queue Service untuk sign JWT
- **Harus sama persis** di semua service — satu karakter beda = semua token invalid

**Kode yang terdampak:**
- `booking-service/pkg/middleware/auth.go` → `RequireAccessToken(secret)`
- `event-service/pkg/middleware/auth.go`   → `RequireAccessToken(secret)`
- `payment-service/pkg/middleware/auth.go` → `RequireAccessToken(secret)`
- `booking-service/internal/booking/infrastructure/cache/cache_repo.go` → `ValidateAccessToken`

**Validasi setelah integrasi:**
```bash
# Token dari Queue Service BE-1 harus bisa di-verify:
curl -H "X-Access-Token: <token dari BE-1>" http://localhost:8081/api/booking/v1 -v
# Harus 400 (body kosong), bukan 401
```

---

## 2. Dukcapil Verification Service

**Status saat ini:** mock dengan `mock-dukcapil/main.go` di port 8085 — selalu return `valid:true`

**File yang perlu diubah:**
- `booking-service/.env` → `DUKCAPIL_BASE_URL=<URL dari BE-1>`
- `booking-service/.env` → `DUKCAPIL_FAIL_OPEN=false` (di production)

**Cara dapat nilai dari BE-1:**
- Minta URL endpoint Dukcapil mock dari BE-1 (biasanya `http://<host>:808x/internal/dukcapil`)
- Konfirmasi format request/response sama:
  ```json
  // Request: POST /internal/dukcapil/verify
  { "nik": "...", "nama": "...", "tglLahir": "...", "namaIbu": "..." }
  // Response:
  { "status": "00000", "message": "OK", "data": { "valid": true/false } }
  ```

**Kode yang terdampak:**
- `booking-service/internal/booking/infrastructure/http/dukcapil_client.go` → `Verify()`
- Jika ada auth header tambahan → update `Verify()` untuk kirim header tersebut

**Validasi setelah integrasi:**
```bash
# Hentikan mock-dukcapil, ubah DUKCAPIL_BASE_URL ke URL BE-1, restart booking-service
# Test booking dengan NIK valid → harus lewat
# Test booking dengan NIK invalid (13 digit) → harus 400 NIK_INVALID
```

---

## 3. Access Token JWT — Struktur Klaim

**Status saat ini:** generate manual via `gen_demo_token.go` dengan klaim minimal

**Konfirmasi dengan BE-1 bahwa klaim JWT berisi:**
```json
{
  "eventId": "uuid-event",
  "bookingTtlExpiresAt": 1234567890,
  "exp": 1234567890,
  "iat": 1234567890
}
```

Jika BE-1 menambahkan klaim lain (misal `userId`, `nik`), update struct ini:
```go
// booking-service/pkg/middleware/auth.go
type AccessTokenClaims struct {
    EventID             string `json:"eventId"`
    QueueToken          string `json:"queueToken"`
    NIK                 string `json:"nik,omitempty"`
    BookingTTLExpiresAt int64  `json:"bookingTtlExpiresAt"`
    jwt.RegisteredClaims
}
```

**Kode yang terdampak:**
- `booking-service/pkg/middleware/auth.go` → `AccessTokenClaims`
- `booking-service/internal/booking/infrastructure/cache/cache_repo.go` → struct `accessClaims`
- `booking-service/internal/booking/application/usecase/create_booking.go` → `req.EventIDFromToken`

---

## 4. Mock Service yang Harus Dihentikan

Saat BE-1 sudah running:

| Mock | Port | Ganti dengan |
|------|------|--------------|
| `mock-dukcapil/main.go` | 8085 | Dukcapil service dari BE-1 |
| `gen_demo_token.go` | — | Token nyata dari `POST /events/{id}/queue` BE-1 |

---

## 5. .env yang Perlu Diupdate Saat Integrasi

```bash
# booking-service/.env
ACCESS_TOKEN_SECRET=<dari BE-1>          # ganti dev-secret
DUKCAPIL_BASE_URL=<URL dari BE-1>        # ganti http://localhost:8085
DUKCAPIL_FAIL_OPEN=false                 # ganti true → false

# event-service/.env
ACCESS_TOKEN_SECRET=<dari BE-1>          # ganti dev-secret

# payment-service/.env
ACCESS_TOKEN_SECRET=<dari BE-1>          # ganti dev-secret
```

---

## 6. Tidak Perlu Diubah (sudah production-ready)

Komponen-komponen berikut **tidak bergantung pada BE-1** dan sudah siap:

| Komponen | Keterangan |
|---|---|
| Kafka topics & events | Sudah sesuai event-contract |
| SSE stock stream | Independen dari BE-1 |
| Midtrans Snap integration | Sudah menggunakan server key sandbox |
| Worker email templates | Sudah menggunakan Gmail SMTP |
| Anti-oversell atomic hold | Tidak bergantung BE-1 |
| TTL sweeper (booking + payment) | Independen dari BE-1 |
| Payment callback verification | Independen dari BE-1 |

---

## 7. Bug Fix yang Sudah Diterapkan ✅

### `stock.changed` — `Available` Aktual (bukan -1)

**File:** `booking-service/internal/booking/application/usecase/create_booking.go`

**Masalah sebelumnya:** `publishPostBooking` mengirim `Available: -1` ke Kafka saat booking HOLD.
Queue-service menyimpan `-1` ke Redis, menyebabkan kategori yang di-hold tidak dihitung
dalam `roomcap` → cap booking room jauh lebih kecil dari seharusnya.

**Fix:** Snapshot DB (`GetAvailableByEvent`) dipindahkan sebelum loop Kafka publish.
Satu kali baca DB dipakai untuk mengisi `Available` aktual di Kafka **dan** Redis SSE.

**Referensi:** `docs/bug_stock_changed_available_minus_one.md`

---

## Quick Integration Test Setelah BE-1 Siap

```bash
# 1. Update .env semua service dengan ACCESS_TOKEN_SECRET dari BE-1
# 2. Stop mock-dukcapil
# 3. Update DUKCAPIL_BASE_URL ke BE-1
# 4. Restart semua service

# 5. Dapatkan token nyata dari Queue Service:
ACCESS_TOKEN=$(curl -s -X POST http://<BE1_HOST>/api/v1/events/<EVENT_ID>/queue \
  -H "Content-Type: application/json" \
  -d '{}' | jq -r '.data.accessToken')

# 6. Test create booking dengan token BE-1:
curl -X POST http://localhost:8081/api/booking/v1/create \
  -H "X-Access-Token: $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "eventId": "...", "email": "...", "items": [...] }'

# 7. Harus sukses dengan status HELD (bukan 401)
```
