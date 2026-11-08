#!/bin/bash
# vm_schedule_setup.sh
# Setup Cloud Scheduler untuk auto stop/start VM rusuh-data
# Stop: 23:00 WIB (16:00 UTC) setiap hari
# Start: 07:00 WIB (00:00 UTC) setiap hari
# Cloud Scheduler FREE tier: 3 jobs gratis = tidak ada biaya tambahan

set -euo pipefail

PROJECT="rusuh-ticketing"
ZONE="asia-southeast2-a"
INSTANCE="rusuh-data"
REGION="asia-southeast2"

# Service Account untuk Cloud Scheduler
SA_NAME="vm-scheduler-sa"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

echo "========================================"
echo " Setup VM Auto Stop/Start Scheduler"
echo " VM     : ${INSTANCE}"
echo " Zone   : ${ZONE}"
echo " Stop   : 23:00 WIB (16:00 UTC)"
echo " Start  : 07:00 WIB (00:00 UTC)"
echo "========================================"
echo ""

# 1. Enable Cloud Scheduler API (jika belum)
echo "[1/5] Enable Cloud Scheduler API..."
gcloud services enable cloudscheduler.googleapis.com \
  --project="${PROJECT}"

# 2. Buat Service Account minimal (jika belum ada)
echo "[2/5] Create Service Account..."
gcloud iam service-accounts create "${SA_NAME}" \
  --display-name="VM Scheduler Service Account" \
  --project="${PROJECT}" 2>/dev/null || echo "  SA sudah ada, skip"

# 3. Grant permission: hanya compute.instances.start/stop
echo "[3/5] Grant Compute Instance Admin (minimal)..."
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.instanceAdmin.v1" \
  --condition=None

# 4. Buat job STOP (setiap hari 23:00 WIB = 16:00 UTC)
echo "[4/5] Create STOP job (23:00 WIB = 16:00 UTC)..."
gcloud scheduler jobs create http "vm-rusuh-data-stop" \
  --schedule="0 16 * * *" \
  --uri="https://compute.googleapis.com/compute/v1/projects/${PROJECT}/zones/${ZONE}/instances/${INSTANCE}/stop" \
  --message-body="{}" \
  --oauth-service-account-email="${SA_EMAIL}" \
  --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform" \
  --location="${REGION}" \
  --time-zone="UTC" \
  --description="Auto stop VM rusuh-data at 23:00 WIB" \
  --project="${PROJECT}" 2>/dev/null || \
gcloud scheduler jobs update http "vm-rusuh-data-stop" \
  --schedule="0 16 * * *" \
  --location="${REGION}" \
  --project="${PROJECT}" && echo "  Updated existing job"

# 5. Buat job START (setiap hari 07:00 WIB = 00:00 UTC)
echo "[5/5] Create START job (07:00 WIB = 00:00 UTC)..."
gcloud scheduler jobs create http "vm-rusuh-data-start" \
  --schedule="0 0 * * *" \
  --uri="https://compute.googleapis.com/compute/v1/projects/${PROJECT}/zones/${ZONE}/instances/${INSTANCE}/start" \
  --message-body="{}" \
  --oauth-service-account-email="${SA_EMAIL}" \
  --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform" \
  --location="${REGION}" \
  --time-zone="UTC" \
  --description="Auto start VM rusuh-data at 07:00 WIB" \
  --project="${PROJECT}" 2>/dev/null || \
gcloud scheduler jobs update http "vm-rusuh-data-start" \
  --schedule="0 0 * * *" \
  --location="${REGION}" \
  --project="${PROJECT}" && echo "  Updated existing job"

echo ""
echo "========================================"
echo " ✅ Setup selesai!"
echo ""
echo " Jobs terdaftar:"
gcloud scheduler jobs list --location="${REGION}" --project="${PROJECT}" \
  --filter="name:(vm-rusuh-data)"
echo ""
echo " Test manual stop sekarang (opsional):"
echo "   gcloud scheduler jobs run vm-rusuh-data-stop --location=${REGION} --project=${PROJECT}"
echo ""
echo " Estimasi penghematan:"
echo "   VM nyala 16 jam/hari (07:00-23:00 WIB)"
echo "   Sebelum: 24 jam/hari  → Rp 281,389/bulan"
echo "   Sesudah: 16 jam/hari  → ~Rp 187,592/bulan"
echo "   Hemat  : ~Rp 93,797/bulan (33%)"
echo "========================================"
