#!/bin/bash
# vm_manual.sh — Start/Stop VM rusuh-data manual
# Usage:
#   ./vm_manual.sh start
#   ./vm_manual.sh stop
#   ./vm_manual.sh status

PROJECT="rusuh-ticketing"
ZONE="asia-southeast2-a"
INSTANCE="rusuh-data"

CMD="${1:-status}"

case "$CMD" in
  start)
    echo "▶ Starting VM ${INSTANCE}..."
    gcloud compute instances start "${INSTANCE}" \
      --zone="${ZONE}" --project="${PROJECT}"
    echo "✅ VM started"
    ;;
  stop)
    echo "⏹ Stopping VM ${INSTANCE}..."
    gcloud compute instances stop "${INSTANCE}" \
      --zone="${ZONE}" --project="${PROJECT}"
    echo "✅ VM stopped"
    ;;
  status)
    STATUS=$(gcloud compute instances describe "${INSTANCE}" \
      --zone="${ZONE}" --project="${PROJECT}" \
      --format="value(status)")
    echo "VM ${INSTANCE}: ${STATUS}"
    ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
