# Apidog Collections — Rusuh Booking Tiket BE-2

Folder ini berisi Postman-compatible collection (v2.1) untuk tiap service.

## File

| File | Service | Port |
|------|---------|------|
| `event-service.json` | Event CRUD + Admin + Internal sold-out | 8082 |
| `booking-service.json` | Create Booking + Status + SSE Stock Stream | 8081 |
| `payment-service.json` | Get Payment Detail + Charge + Callback | 8083 |
| `worker-service.json` | Health check (Kafka consumer, no HTTP) | 8084 |

## Import ke Apidog

1. Buka Apidog
2. **New Project** → nama service (misal "booking-service")
3. **Import** → **Postman Collection** → pilih file `.json`
4. Set variabel `base_url`, `access_token`, dll di **Environment**

## Import ke Postman

1. Buka Postman
2. **Import** → drag-drop file `.json`
3. Set environment variables

## Environment Variables yang Perlu Di-set

| Variable | Cara dapat |
|----------|-----------|
| `admin_token` | JWT dengan `role=admin` dari BE-1 Queue Service |
| `user_token` | JWT user biasa dari BE-1 |
| `access_token` | JWT dari `POST /events/{id}/queue` (Queue Service) — berisi claim `eventId` + `bookingTtlExpiresAt` |
| `booking_id` | UUID dari response `POST /api/v1/bookings` |
| `event_id` | UUID event (seed default: `EVT-001`) |
| `category_id` | UUID kategori (seed default: `CAT-VIP`, `CAT-REG`) |

## Demo Token (tanpa Queue Service)

Bila Queue Service belum siap, generate Access Token dummy:

```bash
cd "/path/to/assessment 2026"
source <(go run gen_demo_token.go)
# ACCESS_TOKEN sudah ter-set di shell
echo $ACCESS_TOKEN
```

Copy nilai tersebut ke variabel `access_token` di Apidog/Postman.

## Test SSE Stock Stream

Apidog tidak bisa render SSE natively. Gunakan curl:

```bash
curl -N \
  -H "X-Access-Token: $ACCESS_TOKEN" \
  -H "Accept: text/event-stream" \
  "http://localhost:8081/api/v1/events/EVT-001/stock/stream"
```

## Signature Midtrans Callback (untuk test)

```bash
# Format: SHA512(orderId + statusCode + grossAmount + serverKey)
ORDER_ID="your-booking-id"
STATUS_CODE="200"
GROSS_AMOUNT="500000.00"
SERVER_KEY="SB-Mid-server-XXXXXXXX"

echo -n "${ORDER_ID}${STATUS_CODE}${GROSS_AMOUNT}${SERVER_KEY}" | sha512sum
```
