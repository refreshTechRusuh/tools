# ============================================================
# Rusuh Booking Tiket — Root Makefile
# ============================================================

.PHONY: up down down-clean logs ps kafka-topics kafka-ui psql demo-token demo health mock-dukcapil check-stock check-bookings

# Start semua infra (postgres, redis, kafka, kafka-ui)
up:
	docker compose up -d
	@echo ""
	@echo "✅ Infra running:"
	@echo "   Postgres  → localhost:5432  (rusuh_booking / postgres / password)"
	@echo "   Redis     → localhost:6379"
	@echo "   Kafka     → localhost:29092"
	@echo "   Kafka UI  → http://localhost:8090"
	@echo ""
	@echo "Jalankan tiap service dengan:"
	@echo "  cd booking-service  && APP_PORT=8081 go run cmd/main.go"
	@echo "  cd event-service    && APP_PORT=8082 go run cmd/main.go"
	@echo "  cd payment-service  && APP_PORT=8083 go run cmd/main.go"
	@echo "  cd worker-service   && go run cmd/main.go"

# Stop semua (data volumes dipertahankan)
down:
	docker compose down

# Stop dan hapus semua data (wipe bersih)
down-clean:
	docker compose down -v
	@echo "⚠️  Semua data dihapus."

# Lihat semua container yang running
ps:
	docker compose ps

# Tail logs semua service
logs:
	docker compose logs -f

# Tail logs kafka saja
logs-kafka:
	docker compose logs -f kafka

# List Kafka topics
kafka-topics:
	docker exec rusuh_kafka kafka-topics --bootstrap-server localhost:9092 --list

# Buka Kafka UI di browser (macOS)
kafka-ui:
	open http://localhost:8090

# Connect ke psql
psql:
	docker exec -it rusuh_postgres psql -U postgres -d rusuh_booking

# Generate Access Token demo (tanpa Queue Service)
# Usage: source <(make demo-token)
demo-token:
	@cd "/Users/alifsn/Documents/master-code/telkomsel/assessment 2026" && \
	  go run gen_demo_token.go

# Cek status semua service (health check)
health:
	@echo "=== Health Check ==="
	@curl -sf http://localhost:8082/sys/ping > /dev/null && echo "✅ event-service  :8082" || echo "❌ event-service  :8082 (down)"
	@curl -sf http://localhost:8081/sys/ping > /dev/null && echo "✅ booking-service:8081" || echo "❌ booking-service:8081 (down)"
	@curl -sf http://localhost:8083/sys/ping > /dev/null && echo "✅ payment-service:8083" || echo "❌ payment-service:8083 (down)"
	@echo ""
	@echo "Kafka UI : http://localhost:8090"

# Jalankan mock-dukcapil service (pengganti BE-1 Dukcapil)
# Port: 8085 — selalu return valid:true untuk NIK 16 digit
mock-dukcapil:
	@echo "🪪  Starting mock-dukcapil on :8085..."
	cd mock-dukcapil && go run main.go

# Cek stok terkini di DB
check-stock:
	docker exec rusuh_postgres psql -U postgres -d rusuh_booking \
	  -c "SELECT tc.name, tc.available, tc.capacity, e.name as event FROM ticket_category tc JOIN event e ON e.id = tc.event_id ORDER BY e.name, tc.name;"

# Lihat semua booking terkini
check-bookings:
	docker exec rusuh_postgres psql -U postgres -d rusuh_booking \
	  -c "SELECT b.id, b.email, b.status, b.payment_expires_at, count(bi.id) as tickets FROM booking b LEFT JOIN booking_item bi ON bi.booking_id = b.id GROUP BY b.id ORDER BY b.created_at DESC LIMIT 10;"
