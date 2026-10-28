# Panduan Run Lokal BE-2 (Tanpa BE-1)

Dokumen ini menjelaskan cara menjalankan semua service BE-2 secara mandiri tanpa bergantung pada BE-1 (Queue Service).

---

## Yang di-mock dari BE-1

| Komponen BE-1 | Solusi |
|---|---|
| Queue Service (Access Token JWT) | `gen_demo_token.go` — generate token langsung |
| Dukcapil Verification API | `mock-dukcapil/` — always valid untuk NIK 16 digit |

---

## Step 1: Isi `.env` di setiap service

> **PENTING**: Isi `MIDTRANS_SERVER_KEY` dengan server key sandbox Midtrans kamu.

### booking-service/.env
```
MIDTRANS_SERVER_KEY=SB-Mid-server-xxxx   ← isi ini
ACCESS_TOKEN_SECRET=dev-secret-change-in-production   ← jangan diubah
```

### payment-service/.env
```
MIDTRANS_SERVER_KEY=SB-Mid-server-xxxx   ← isi ini (harus sama dengan booking-service)
ACCESS_TOKEN_SECRET=dev-secret-change-in-production   ← jangan diubah
```

### worker-service/.env
```
EMAIL_USERNAME=alifsnurdianto@gmail.com   ← sudah terisi
EMAIL_PASSWORD=wdgavdhnlcivogmx           ← sudah terisi (App Password)
```

---

## Step 2: Jalankan infrastruktur

```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026"
make up
```

Tunggu Kafka siap (~15 detik). Cek:
```bash
docker compose ps
# Semua harus "healthy" atau "running"
```

---

## Step 3: Jalankan mock-dukcapil (Terminal 1)

```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026"
make mock-dukcapil
# → 🪪  mock-dukcapil listening on :8085
```

Verifikasi:
```bash
curl http://localhost:8085/sys/ping
# → {"status":"00000","message":"mock-dukcapil ok","data":{}}
```

---

## Step 4: Jalankan 4 service (Terminal 2-5)

**Terminal 2 — event-service (port 8082):**
```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/event-service"
make run
```

**Terminal 3 — booking-service (port 8081):**
```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/booking-service"
make run
```

**Terminal 4 — payment-service (port 8083):**
```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/payment-service"
make run
```

**Terminal 5 — worker-service:**
```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/worker-service"
make run
```

Health check semua:
```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026"
make health
```

---

## Step 5: Generate Access Token

```bash
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026"
source <(go run gen_demo_token.go)

# Hasilnya:
# export ACCESS_TOKEN="eyJ..."
# export EVENT_ID="018f2c1a-0000-7000-8000-0000000000a1"
```

Token berlaku **2 jam**. Generate ulang jika expired.

---

## Step 6: Demo alur lengkap

### 6.1 Lihat daftar event
```bash
curl http://localhost:8082/api/event/v1/list | jq
```

### 6.2 Create Booking (butuh Access Token)
```bash
curl -s -X POST http://localhost:8081/api/booking/v1/create \
  -H "X-Access-Token: $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "'$EVENT_ID'",
    "email": "alifsnurdianto@gmail.com",
    "items": [{
      "categoryId": "cat-reg-001",
      "attendees": [{
        "nik": "3273010101900001",
        "nama": "Budi Santoso",
        "tglLahir": "1990-01-01",
        "namaIbu": "Siti Aminah"
      }]
    }]
  }' | jq

# Response: {"bookingId": "uuid", "status": "HELD", "total": 500000, "paymentExpiresAt": "..."}
# Simpan bookingId:
export BOOKING_ID="<uuid dari response>"
```

**Cek email masuk** — email #1 "Instruksi Pembayaran" dikirim otomatis ke `alifsnurdianto@gmail.com` oleh worker-service via Kafka.

### 6.3 Lihat status booking
```bash
curl -H "X-Access-Token: $ACCESS_TOKEN" \
  http://localhost:8081/api/booking/v1/$BOOKING_ID | jq
```

### 6.4 Lihat detail payment (metode tersedia)
```bash
curl -H "X-Access-Token: $ACCESS_TOKEN" \
  http://localhost:8083/api/booking/v1/$BOOKING_ID/payment | jq
```

### 6.5 Charge payment (Midtrans Snap)
```bash
curl -s -X POST http://localhost:8083/api/payment/v1/charge \
  -H "X-Access-Token: $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "bookingId": "'$BOOKING_ID'",
    "method": "qris",
    "idempotencyKey": "idem-'$BOOKING_ID'-qris-001"
  }' | jq

# Response: {"paymentId": "...", "status": "PENDING", "snapToken": "...", "redirectUrl": "..."}
export SNAP_TOKEN="<snapToken dari response>"
```

### 6.6 Selesaikan pembayaran di Midtrans Snap
Buka URL di browser (dari `redirectUrl`) atau gunakan Snap popup.  
Atau simulate via Midtrans callback langsung (lihat 6.7).

### 6.7 Simulate Midtrans callback (bayar sukses)
Generate signature dulu:
```bash
ORDER_ID="$BOOKING_ID"
STATUS_CODE="200"
GROSS_AMOUNT="500000.00"   # sesuai total booking
SERVER_KEY="SB-Mid-server-xxxx"   # ganti dengan server key kamu

SIG=$(echo -n "${ORDER_ID}${STATUS_CODE}${GROSS_AMOUNT}${SERVER_KEY}" | shasum -a 512 | cut -d' ' -f1)

curl -s -X POST http://localhost:8083/api/payment/v1/callback \
  -H "Content-Type: application/json" \
  -d '{
    "order_id": "'$BOOKING_ID'",
    "transaction_status": "settlement",
    "status_code": "200",
    "gross_amount": "'$GROSS_AMOUNT'",
    "payment_type": "qris",
    "signature_key": "'$SIG'",
    "fraud_status": "accept"
  }' | jq
```

**Cek email masuk** — email #2 "E-Tiket Boarding Pass" dikirim otomatis.

---

## Checklist setelah semua step di atas

- [ ] `make health` → semua ✅
- [ ] `mock-dukcapil` running di :8085
- [ ] Event list muncul dari event-service
- [ ] Booking berhasil dibuat (status HELD)
- [ ] Email #1 masuk di inbox `alifsnurdianto@gmail.com`
- [ ] Payment charge → `snapToken` returned
- [ ] Callback simulate → booking jadi PAID
- [ ] Email #2 masuk di inbox

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `ACCESS_TOKEN tidak valid` | `source <(go run gen_demo_token.go)` ulang |
| `dukcapil service unreachable` | Pastikan `make mock-dukcapil` running |
| `kafka publish failed` | Cek `docker compose ps` — kafka harus healthy |
| `MIDTRANS_SERVER_KEY` kosong | Isi di `payment-service/.env` |
| Email tidak masuk | Cek worker-service log, cek spam folder |
| `Stok tidak tersedia` | `make check-stock`, `make down-clean && make up` untuk reset |
