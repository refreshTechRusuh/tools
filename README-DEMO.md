# 🎯 Panduan Demo BE-2 — Hari Sidang

Panduan ini berisi langkah-langkah yang bisa kamu ikuti secara berurutan di hari sidang.

---

## Sebelum Sidang (H-1 atau pagi hari)

### 1. Pastikan semua repo ter-pull ke branch terbaru

```bash
for repo in booking-service event-service payment-service worker-service; do
  echo "=== $repo ===" && cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/$repo" && \
    git fetch origin && git status
done
```

### 2. Build semua service

```bash
for repo in booking-service event-service payment-service worker-service; do
  echo -n "$repo: "
  cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/$repo" && go build ./... && echo "✅"
done
```

### 3. Jalankan semua test

```bash
for repo in booking-service event-service payment-service worker-service; do
  echo "=== $repo ==="
  cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/$repo" && \
    go test -race ./... 2>&1 | grep -E "^(ok|FAIL)"
done
```

---

## Hari Sidang — Urutan Startup

### Step 1: Start infrastruktur

```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026"
make up
```

Tunggu ~30 detik sampai Kafka selesai inisialisasi. Cek:

```bash
make ps
# Semua status harus "healthy" atau "running"
```

### Step 2: Siapkan `.env` di setiap service

> Catatan: `.env.local` sudah berisi semua config lokal. Copy ke masing-masing repo dulu bila belum.

```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026"
cp .env.local booking-service/.env
cp .env.local event-service/.env
cp .env.local payment-service/.env
cp .env.local worker-service/.env
```

**WAJIB diisi setelah koordinasi dengan BE-1:**

```bash
# Di semua .env — ganti dengan nilai yang sama dipakai Queue Service
ACCESS_TOKEN_SECRET=<shared-secret-dari-BE1>
```

### Step 3: Jalankan 4 service (4 terminal terpisah)

```bash
# Terminal 1
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/event-service"
APP_PORT=8082 go run cmd/main.go

# Terminal 2
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/booking-service"
APP_PORT=8081 go run cmd/main.go

# Terminal 3
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/payment-service"
APP_PORT=8083 go run cmd/main.go

# Terminal 4 (worker — tidak ada port HTTP)
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/worker-service"
go run cmd/main.go
```

### Step 4: Verifikasi semua service hidup

```bash
curl http://localhost:8081/sys/ping   # booking
curl http://localhost:8082/sys/ping   # event
curl http://localhost:8083/sys/ping   # payment
```

Output yang diharapkan:
```json
{"status":"00000","message":"pong","data":{}}
```

---

## Demo Saat Sidang

### 🟢 Demo 1: Katalog event (publik, tanpa auth)

```bash
curl -s http://localhost:8082/api/event/v1/list | python3 -m json.tool
```

Output menunjukkan 2 event seed + status.

---

### 🟢 Demo 2: Admin buat event dan kategori

```bash
# Buat event baru
curl -s -X POST http://localhost:8082/api/event/v1/admin/create-event \
  -H "Content-Type: application/json" \
  -d '{"name":"Demo Sidang Concert","status":"on_sale"}' | python3 -m json.tool

# Simpan eventId dari response, lalu buat kategori
EVENT_ID="<id-dari-response>"
curl -s -X POST "http://localhost:8082/api/v1/admin/events/$EVENT_ID/categories" \
  -H "Content-Type: application/json" \
  -d '{"name":"VIP","price":1000000,"capacity":10}' | python3 -m json.tool
```

Tunjukkan bahwa: **available = capacity = 10** saat dibuat.

---

### 🟢 Demo 3: Buat booking (hold stok atomic)

> Butuh Access Token dari Queue Service. Kalau Queue Service belum ada, gunakan token yang di-generate dengan `gen_demo_token.go`.

```bash
# Gunakan event seed yang sudah ada
curl -s -X POST http://localhost:8081/api/booking/v1/create \
  -H "Content-Type: application/json" \
  -H "X-Access-Token: $ACCESS_TOKEN" \
  -d '{
    "eventId": "018f2c1a-0000-7000-8000-0000000000a1",
    "email": "demo@rusuh.com",
    "items": [{
      "categoryId": "cat-vip-001",
      "attendees": [{
        "nik": "3273000000000001",
        "nama": "Budi Santoso",
        "tglLahir": "1992-05-10",
        "namaIbu": "Siti Rahayu"
      }]
    }]
  }' | python3 -m json.tool
```

**Poin diskusi:**
- Status = `HELD` (bukan PAID)
- `paymentExpiresAt` = 10 menit dari sekarang
- Stok `cat-vip-001` sudah berkurang 1 di DB

---

### 🟢 Demo 4: SSE stok realtime (di terminal terpisah)

```bash
# Buka di terminal terpisah SEBELUM melakukan booking:
curl -N "http://localhost:8081/api/booking/v1/event/018f2c1a-0000-7000-8000-0000000000a1/stock/stream" \
  -H "X-Access-Token: $ACCESS_TOKEN"
```

Lalu lakukan booking di terminal lain → lihat SSE menerima update `available` berkurang.

**Poin diskusi:**
- Initial snapshot dikirim saat connect (tidak perlu tunggu event pertama)
- Update datang via Redis Pub/Sub dalam milidetik

---

### 🟢 Demo 5: Payment — metode dinamis

```bash
BOOKING_ID="<dari-demo-3>"
curl -s "http://localhost:8083/api/booking/v1/$BOOKING_ID/payment" \
  -H "X-Access-Token: $ACCESS_TOKEN" | python3 -m json.tool
```

**Tunjukkan:** `bca_va.enabled = false` bila TTL < 180s, `qris.enabled = true` bila TTL >= 60s.

---

### 🟢 Demo 6: Callback Midtrans (simulasi bayar sukses)

```bash
BOOKING_ID="<dari-demo-3>"
# Hitung signature: sha512(bookingId + "200" + "1000000.00" + SERVER_KEY)
SIGNATURE=$(echo -n "${BOOKING_ID}2001000000.00SB-Mid-server-xxxx" | sha512sum | cut -d' ' -f1)

curl -s -X POST http://localhost:8083/api/payment/v1/callback \
  -H "Content-Type: application/json" \
  -d "{
    \"order_id\": \"$BOOKING_ID\",
    \"transaction_status\": \"settlement\",
    \"status_code\": \"200\",
    \"gross_amount\": \"1000000.00\",
    \"payment_type\": \"qris\",
    \"signature_key\": \"$SIGNATURE\"
  }" | python3 -m json.tool
```

Lalu cek booking:
```bash
curl -s "http://localhost:8081/api/booking/v1/$BOOKING_ID" \
  -H "X-Access-Token: $ACCESS_TOKEN" | python3 -m json.tool
# status harus berubah ke PAID
```

---

### 🟢 Demo 7: Test anti-oversell (bukti sidang utama)

```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/booking-service"
go test -race -run TestAntiOversell_Concurrent -v ./internal/booking/application/usecase/...
```

**Output yang diharapkan:**
```
=== RUN   TestAntiOversell_Concurrent
--- PASS: TestAntiOversell_Concurrent (0.00s)
```

**Penjelasan:** 10 goroutine berebut stok=1 secara bersamaan, tepat 1 yang berhasil, sisanya `409 STOCK_UNAVAILABLE`. `available` di DB tidak pernah < 0.

---

### 🟢 Demo 8: Test idempotency callback

```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/payment-service"
go test -race -run TestIdempoten_Concurrent -v ./internal/payment/application/usecase/...
```

10 goroutine kirim callback bersamaan → tepat 1 diproses.

---

### 🟢 Demo 9: Kafka UI — lihat event yang di-publish

Buka: **http://localhost:8090**

Topics yang bisa ditunjukkan:
- `booking.created` — setelah demo booking
- `payment.succeeded` — setelah demo callback
- `slot.released` — setelah payment sukses

---

## Pertanyaan Sidang — Jawaban Singkat

### "Bagaimana anti-oversell bekerja?"

```sql
UPDATE ticket_category
   SET available = available - qty
 WHERE id = :categoryId AND available >= qty
-- 0 row = stok habis = ROLLBACK seluruh transaksi
```
Satu query per kategori, semua dalam **satu transaksi pgx**. 0 row affected = tidak ada stok yang berubah = rollback.

---

### "Kenapa tidak bisa oversell walaupun banyak request bersamaan?"

PostgreSQL `UPDATE` dengan `WHERE available >= qty` adalah **atomic di level row**. Dua `UPDATE` bersamaan untuk row yang sama akan dieksekusi serial (row lock otomatis). Satu menang, satu mendapat `0 rows affected`.

---

### "Bagaimana booking bisa gagal kalau Queue sudah limit?"

Queue menjamin `bookingRoomCap = floor(stok/3)` orang boleh submit booking. Tapi `WHERE available >= qty` tetap ada sebagai **defense-in-depth** — kalau ada bug di Queue atau ada retry yang tidak terduga, query ini jadi last line of defense.

---

### "Bagaimana idempotency callback Midtrans?"

```sql
INSERT INTO payment_callback_log (idempotency_key, ...)
VALUES (order_id + ':' + transaction_status, ...)
ON CONFLICT DO NOTHING;
-- RowsAffected == 0 → sudah ada → skip
```
Karena `idempotency_key` adalah PRIMARY KEY, konflik langsung ditangani di DB level, tidak perlu lock atau check-then-insert yang bisa race.

---

### "Bagaimana disable metode bayar bekerja?"

```go
enabled = remainingSeconds >= method.EstSeconds
// BCA VA: enabled = (sisa TTL >= 180s)
// QRIS:   enabled = (sisa TTL >= 60s)
```
Dihitung **server-side** saat `GET /bookings/{id}/payment`. `POST /payments/charge` juga enforce ulang — tidak percaya nilai `enabled` dari klien.

---

### "Bagaimana SSE stok tidak ada gap saat client connect?"

Snapshot DB dibaca **sebelum** subscribe Redis Pub/Sub:
```
1. READ snapshot dari DB (stok current)
2. SUBSCRIBE ke Redis channel
3. Kirim snapshot ke client
4. Forward semua Pub/Sub messages ke client
```
Tidak ada window dimana update bisa terlewat.

---

### "Bagaimana sweeper TTL bekerja?"

Goroutine yang jalan tiap 30 detik:
```sql
SELECT id FROM booking
WHERE status='HELD' AND payment_expires_at < NOW()
LIMIT 50
FOR UPDATE SKIP LOCKED  -- aman multi-instance
```
`FOR UPDATE SKIP LOCKED` memastikan dua instance sweeper tidak memproses booking yang sama.

---

## Troubleshooting

| Masalah | Solusi |
|---|---|
| Kafka tidak start | `docker compose logs kafka` — cek zookeeper health dulu |
| Service tidak connect ke DB | `make psql` → `\l` → cek `rusuh_booking` ada |
| Access Token invalid | Pastikan `ACCESS_TOKEN_SECRET` sama di semua service |
| SSE tidak menerima update | Cek booking-service log — Redis Pub/Sub subscribe error? |
| Email tidak terkirim | Worker-service — cek `EMAIL_PASSWORD` Gmail App Password, bukan password login |
| `409 STOCK_UNAVAILABLE` | Stok = 0 di DB. `make psql` → `SELECT id, name, available FROM ticket_category;` |

---

## Reset Demo (kalau mau ulang dari awal)

```bash
# Wipe semua data dan mulai bersih
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026"
make down-clean
make up
# Tunggu ~30 detik, lalu jalankan ulang service
```

Seed data (2 event + 3 kategori) akan otomatis dibuat ulang dari `docker/postgres/init/001_init.sql`.
