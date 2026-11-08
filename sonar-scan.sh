#!/usr/bin/env bash
# sonar-scan.sh — Setup SonarQube Docker + scan semua 4 BE-2 services
# Usage: ./sonar-scan.sh [--token <admin_token>]
set -uo pipefail   # no -e: handle errors manually untuk debug yang lebih baik

BASE="$(cd "$(dirname "$0")/.." && pwd)"
SONAR_URL="http://localhost:9000"
SONAR_ADMIN_PASS="${SONAR_ADMIN_PASS:-}"  # set via env: export SONAR_ADMIN_PASS=xxx
SONAR_TOKEN="${SONAR_TOKEN:-}"  # bisa di-pass via env: SONAR_TOKEN=xxx ./sonar-scan.sh
SERVICES=("booking-service" "event-service" "payment-service" "worker-service")

# ─────────────────────────────────────────────────────────────
# 1. Check dependencies
# ─────────────────────────────────────────────────────────────
check_deps() {
  for cmd in docker sonar-scanner go; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "❌ '$cmd' tidak ditemukan. Install dulu:"
      case "$cmd" in
        docker)        echo "   https://docs.docker.com/get-docker/" ;;
        sonar-scanner) echo "   brew install sonar-scanner" ;;
        go)            echo "   https://go.dev/dl/" ;;
      esac
      exit 1
    fi
  done
  echo "✅ Dependencies OK (docker, sonar-scanner, go)"
}

# ─────────────────────────────────────────────────────────────
# 2. Start SonarQube container (idempotent)
# ─────────────────────────────────────────────────────────────
start_sonarqube() {
  if docker ps --filter name=sonarqube --format '{{.Names}}' | grep -q sonarqube; then
    echo "✅ SonarQube sudah berjalan"
    return
  fi

  if docker ps -a --filter name=sonarqube --format '{{.Names}}' | grep -q sonarqube; then
    echo "▶ Memulai container sonarqube yang sudah ada..."
    docker start sonarqube
  else
    echo "▶ Membuat container sonarqube baru..."
    docker run -d --name sonarqube \
      -p 9000:9000 \
      -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
      sonarqube:community
  fi

  echo -n "⏳ Menunggu SonarQube siap"
  for i in $(seq 1 60); do
    if curl -sf "$SONAR_URL/api/system/status" | grep -q '"status":"UP"'; then
      echo " ✅"
      return
    fi
    echo -n "."
    sleep 3
  done
  echo ""
  echo "❌ SonarQube tidak siap setelah 3 menit. Cek: docker logs sonarqube"
  exit 1
}

# ─────────────────────────────────────────────────────────────
# 3. Verifikasi admin bisa login (skip jika sudah dikonfigurasi)
# ─────────────────────────────────────────────────────────────
setup_admin() {
  if [ -z "$SONAR_ADMIN_PASS" ]; then
    echo "❌ Set password dulu: export SONAR_ADMIN_PASS=<password_sonarqube_kamu>"
    exit 1
  fi

  # Cek apakah password saat ini sudah benar
  VALID=$(curl -s -u "admin:${SONAR_ADMIN_PASS}" \
    "$SONAR_URL/api/authentication/validate" | python3 -c \
    "import json,sys; print(json.load(sys.stdin).get('valid','false'))" 2>/dev/null)

  if [ "$VALID" = "True" ] || [ "$VALID" = "true" ]; then
    echo "✅ Admin login OK"
    return 0
  fi

  # Belum diubah — coba ganti dari default 'admin'
  echo "▶ Mengubah password admin default..."
  HTTP=$(curl -so /dev/null -w "%{http_code}" -X POST -u "admin:admin" \
    "$SONAR_URL/api/users/change_password" \
    --data-urlencode "login=admin" \
    --data-urlencode "previousPassword=admin" \
    --data-urlencode "password=${SONAR_ADMIN_PASS}")

  if [ "$HTTP" = "204" ] || [ "$HTTP" = "200" ]; then
    echo "✅ Password berhasil diubah"
  else
    echo "❌ Gagal ubah password (HTTP $HTTP). Pastikan password di SONAR_ADMIN_PASS sudah benar."
    echo "   Edit tools/sonar-scan.sh baris SONAR_ADMIN_PASS sesuai password SonarQube kamu."
    exit 1
  fi
}

# ─────────────────────────────────────────────────────────────
# 4. Buat/ambil token untuk scan
# ─────────────────────────────────────────────────────────────
ensure_token() {
  if [ -n "$SONAR_TOKEN" ]; then
    echo "✅ Menggunakan token dari env SONAR_TOKEN"
    return
  fi

  echo "▶ Membuat scan token..."
  RESP=$(curl -sf -X POST \
    -u "admin:${SONAR_ADMIN_PASS}" \
    "$SONAR_URL/api/user_tokens/generate" \
    -d "name=scan-token-$(date +%s)&type=GLOBAL_ANALYSIS_TOKEN")
  SONAR_TOKEN=$(echo "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
  echo "✅ Token berhasil dibuat (disimpan di SONAR_TOKEN)"
}

# ─────────────────────────────────────────────────────────────
# 5. Generate coverage + scan per service
# ─────────────────────────────────────────────────────────────
scan_service() {
  local svc="$1"
  local dir="$BASE/$svc"

  echo ""
  echo "════════════════════════════════════════"
  echo "  Scanning: $svc"
  echo "════════════════════════════════════════"

  cd "$dir"

  # Generate coverage report
  echo "▶ Generating coverage..."
  go test ./internal/... -coverprofile=coverage.out -count=1 -timeout 120s \
    2>&1 | tail -3

  # Run sonar-scanner
  echo "▶ Running sonar-scanner..."
  sonar-scanner \
    -Dsonar.token="$SONAR_TOKEN" \
    -Dsonar.host.url="$SONAR_URL" \
    2>&1 | grep -E "INFO: ANALYSIS|ERROR:|WARN:|Quality Gate|EXECUTION"

  echo "✅ $svc done → ${SONAR_URL}/dashboard?id=rusuh-${svc}"
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════"
echo "  SonarQube Scan — BE-2 Services"
echo "═══════════════════════════════════════════"

check_deps
start_sonarqube
setup_admin
ensure_token

for svc in "${SERVICES[@]}"; do
  scan_service "$svc"
done

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ Semua service selesai di-scan!"
echo "  Buka: ${SONAR_URL}/projects"
echo "═══════════════════════════════════════════"
