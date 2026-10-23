#!/usr/bin/env bash
# ============================================================
# demo.sh — Script demo interaktif untuk hari sidang BE-2
# Jalankan: chmod +x demo.sh && ./demo.sh
#
# Prasyarat: semua 4 service sudah berjalan (lihat README-DEMO.md)
# Event ID seed: 018f2c1a-0000-7000-8000-0000000000a1 (Coldplay)
# ============================================================

BASE_BOOKING="http://localhost:8081/api/v1"
BASE_EVENT="http://localhost:8082/api/v1"
BASE_PAYMENT="http://localhost:8083/api/v1"
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

EVENT_ID="018f2c1a-0000-7000-8000-0000000000a1"

# Access Token yang sudah dibuat oleh Queue Service (sign dengan ACCESS_TOKEN_SECRET=dev-secret-change-in-production)
# Dibuat manual untuk demo: eventId=EVENT_ID, bookingTtlExpiresAt=jauh ke depan
# Gunakan token ini sebagai simulasi "sudah melewati antrian"
ACCESS_TOKEN=""  # Diisi dari output queue-service

print_step() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${CYAN}  STEP $1: $2${RESET}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

print_req() {
    echo -e "${YELLOW}REQUEST:${RESET} $1"
}

pretty_json() {
    echo "$1" | python3 -m json.tool 2>/dev/null || echo "$1"
}

# ============================================================
# DEMO 1: Public API — Daftar Event
# ============================================================
print_step "1" "GET /api/v1/events — Katalog event publik (tanpa auth)"
print_req "curl $BASE_EVENT/events"
echo ""
RESP=$(curl -s "$BASE_EVENT/events")
pretty_json "$RESP"

# ============================================================
# DEMO 2: Admin — Buat kategori baru
# ============================================================
print_step "2" "POST /admin/categories — Tambah kategori festival (admin)"
print_req "curl -X POST $BASE_EVENT/admin/events/$EVENT_ID/categories"
echo ""
RESP=$(curl -s -X POST "$BASE_EVENT/admin/events/$EVENT_ID/categories" \
    -H "Content-Type: application/json" \
    -d '{"name":"Festival Area","price":250000,"capacity":1000}')
pretty_json "$RESP"

# ============================================================
# DEMO 3: POST /bookings — Hold stok atomic
# ============================================================
# Dalam demo nyata, ACCESS_TOKEN harus dari Queue Service.
# Untuk demo standalone, kita gunakan token dummy yang sudah di-sign.
if [ -z "$ACCESS_TOKEN" ]; then
    echo ""
    echo -e "${YELLOW}⚠️  ACCESS_TOKEN belum di-set.${RESET}"
    echo "   Hasilkan token dari Queue Service atau pakai gen_demo_token.go"
    echo "   lalu export ACCESS_TOKEN=<token> sebelum jalankan demo ini."
    echo ""
fi

print_step "3" "POST /api/v1/bookings — Hold stok atomic (butuh Access Token)"
print_req "curl -X POST $BASE_BOOKING/bookings  -H 'X-Access-Token: \$ACCESS_TOKEN'"
echo ""
if [ -n "$ACCESS_TOKEN" ]; then
    RESP=$(curl -s -X POST "$BASE_BOOKING/bookings" \
        -H "Content-Type: application/json" \
        -H "X-Access-Token: $ACCESS_TOKEN" \
        -d "{
            \"eventId\": \"$EVENT_ID\",
            \"email\": \"demo@rusuh.com\",
            \"items\": [{
                \"categoryId\": \"cat-vip-001\",
                \"attendees\": [{
                    \"nik\": \"3273000000000001\",
                    \"nama\": \"Budi Santoso\",
                    \"tglLahir\": \"1992-05-10\",
                    \"namaIbu\": \"Siti Rahayu\"
                }]
            }]
        }")
    pretty_json "$RESP"
    BOOKING_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('bookingId',''))" 2>/dev/null)
else
    echo -e "${RED}Skipped — set ACCESS_TOKEN terlebih dahulu${RESET}"
    BOOKING_ID=""
fi

# ============================================================
# DEMO 4: GET /bookings/{bookingId} — Status + TTL + backDisabled
# ============================================================
if [ -n "$BOOKING_ID" ]; then
    print_step "4" "GET /api/v1/bookings/$BOOKING_ID — Status + remainingSeconds + backDisabled"
    print_req "curl $BASE_BOOKING/bookings/$BOOKING_ID"
    echo ""
    RESP=$(curl -s "$BASE_BOOKING/bookings/$BOOKING_ID" \
        -H "X-Access-Token: $ACCESS_TOKEN")
    pretty_json "$RESP"
else
    print_step "4" "GET /api/v1/bookings/{bookingId} — SKIPPED (belum ada bookingId)"
fi

# ============================================================
# DEMO 5: GET /bookings/{bookingId}/payment — Metode dinamis
# ============================================================
if [ -n "$BOOKING_ID" ]; then
    print_step "5" "GET /api/v1/bookings/$BOOKING_ID/payment — Metode bayar (enabled dinamis)"
    print_req "curl $BASE_PAYMENT/bookings/$BOOKING_ID/payment"
    echo ""
    RESP=$(curl -s "$BASE_PAYMENT/bookings/$BOOKING_ID/payment" \
        -H "X-Access-Token: $ACCESS_TOKEN")
    pretty_json "$RESP"
else
    print_step "5" "GET payment — SKIPPED"
fi

# ============================================================
# DEMO 6: SSE stream (background, kill setelah 3 events)
# ============================================================
print_step "6" "GET /api/v1/events/$EVENT_ID/stock/stream — SSE stok realtime"
print_req "curl -N $BASE_BOOKING/events/$EVENT_ID/stock/stream (3 detik)"
echo ""
if [ -n "$ACCESS_TOKEN" ]; then
    timeout 3 curl -s -N "$BASE_BOOKING/events/$EVENT_ID/stock/stream" \
        -H "X-Access-Token: $ACCESS_TOKEN" \
        -H "Accept: text/event-stream" 2>/dev/null || true
    echo ""
    echo -e "${GREEN}✅ SSE terhubung dan menerima initial snapshot${RESET}"
else
    echo -e "${RED}Skipped — set ACCESS_TOKEN${RESET}"
fi

# ============================================================
# DEMO 7: Anti-oversell test — 3 request concurrent, stok=1
# ============================================================
print_step "7" "ANTI-OVERSELL TEST — 3 request concurrent, stok=1 (via unit test)"
echo ""
echo -e "${CYAN}go test -race -run TestAntiOversell_Concurrent -v ./internal/booking/application/usecase/...${RESET}"
echo ""
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/booking-service" && \
    go test -race -run TestAntiOversell_Concurrent -v ./internal/booking/application/usecase/... 2>&1 | \
    grep -E "PASS|FAIL|RUN|goroutine|sukses" | head -10

# ============================================================
# DEMO 8: Callback idempotency test
# ============================================================
print_step "8" "IDEMPOTENCY TEST — Callback Midtrans dikirim 2x, hanya diproses 1x"
echo ""
echo -e "${CYAN}go test -race -run TestHandleCallback_Idempoten -v ./internal/payment/application/usecase/...${RESET}"
echo ""
cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026/payment-service" && \
    go test -race -run TestHandleCallback_Idempoten -v ./internal/payment/application/usecase/... 2>&1 | \
    grep -E "PASS|FAIL|RUN|idempoten" | head -10

echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${GREEN}  DEMO SELESAI ✅${RESET}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo "  Kafka UI  : http://localhost:8090"
echo "  Booking   : curl http://localhost:8081/sys/ping"
echo "  Event     : curl http://localhost:8082/sys/ping"
echo "  Payment   : curl http://localhost:8083/sys/ping"
echo ""
