// gen_demo_token.go — Generate Access Token demo (tanpa Queue Service, tanpa dependency eksternal)
//
// Run:   go run gen_demo_token.go
// Shell: source <(go run gen_demo_token.go)
//
// Hasilkan X-Access-Token valid untuk event seed Coldplay.
// TTL 2 jam. Secret: dev-secret-change-in-production (sama dengan .env semua service).
//
// Override env:
//   ACCESS_TOKEN_SECRET=secret EVENT_ID=uuid go run gen_demo_token.go
//
// Flag:
//   --event-id <uuid>       Override eventId (atau gunakan env EVENT_ID)
//   --expires-at <unix>     Set bookingTtlExpiresAt ke unix timestamp tertentu
//                           (pakai 1 untuk masa lalu = expired token, test INT-4)
//   --raw                   Output hanya token (tanpa export shell syntax)

package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

func b64(data []byte) string {
	return strings.TrimRight(base64.URLEncoding.EncodeToString(data), "=")
}

func main() {
	secret := os.Getenv("ACCESS_TOKEN_SECRET")
	if secret == "" {
		secret = "dev-secret-change-in-production"
	}

	eventID := os.Getenv("EVENT_ID")
	if eventID == "" {
		// Seed event: Coldplay Music of the Spheres 2026
		eventID = "018f2c1a-0000-7000-8000-0000000000a1"
	}

	now := time.Now()
	ttl := 2 * time.Hour
	expiresAt := now.Add(ttl)
	rawOutput := false

	// Parse flags
	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--event-id":
			if i+1 < len(args) {
				eventID = args[i+1]
				i++
			}
		case "--expires-at":
			if i+1 < len(args) {
				ts, err := strconv.ParseInt(args[i+1], 10, 64)
				if err == nil {
					expiresAt = time.Unix(ts, 0)
				}
				i++
			}
		case "--raw":
			rawOutput = true
		}
	}

	// JWT header
	header := map[string]string{"alg": "HS256", "typ": "JWT"}
	hb, _ := json.Marshal(header)

	// JWT claims (sesuai AccessTokenClaims di booking-service)
	claims := map[string]interface{}{
		"eventId":             eventID,
		"queueToken":          "mock-queue-token-for-dev",
		"bookingTtlExpiresAt": expiresAt.Unix(),
		"exp":                 expiresAt.Unix(),
		"iat":                 now.Unix(),
	}
	cb, _ := json.Marshal(claims)

	// Sign HS256
	unsigned := b64(hb) + "." + b64(cb)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(unsigned))
	sig := b64(mac.Sum(nil))

	token := unsigned + "." + sig

	if rawOutput {
		// Output token saja — untuk dipakai langsung di script
		fmt.Print(token)
		return
	}

	// Output untuk `source <(...)`
	fmt.Printf("export ACCESS_TOKEN=\"%s\"\n", token)
	fmt.Printf("export EVENT_ID=\"%s\"\n", eventID)

	expired := expiresAt.Before(now)
	expiredMark := ""
	if expired {
		expiredMark = " ⚠️  EXPIRED (untuk negative test)"
	}

	fmt.Fprintf(os.Stderr, "\n✅ Demo Access Token generated\n")
	fmt.Fprintf(os.Stderr, "   eventId  : %s\n", eventID)
	fmt.Fprintf(os.Stderr, "   secret   : %s\n", secret)
	fmt.Fprintf(os.Stderr, "   expires  : %s (TTL %s)%s\n",
		expiresAt.Format("15:04:05"), ttl, expiredMark)
	fmt.Fprintf(os.Stderr, "\nUsage:\n")
	fmt.Fprintf(os.Stderr, "  source <(go run gen_demo_token.go)\n")
	fmt.Fprintf(os.Stderr, "  curl -H \"X-Access-Token: $ACCESS_TOKEN\" http://localhost:8081/api/booking/v1/create ...\n\n")
}
