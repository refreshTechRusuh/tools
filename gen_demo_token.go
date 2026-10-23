// gen_demo_token.go — Generate Access Token demo (tanpa Queue Service, tanpa dependency eksternal)
// Digunakan saat sidang standalone (BE-2 demo tanpa BE-1).
//
// Run: go run gen_demo_token.go
// Atau: source <(go run gen_demo_token.go)
//
// Hasilkan X-Access-Token yang valid untuk event seed Coldplay.
// TTL 30 menit. Secret: dev-secret-change-in-production (sama dengan .env.local)

package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
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
		eventID = "018f2c1a-0000-7000-8000-0000000000a1"
	}

	now := time.Now()
	expiresAt := now.Add(30 * time.Minute)

	// JWT header
	header := map[string]string{"alg": "HS256", "typ": "JWT"}
	hb, _ := json.Marshal(header)

	// JWT claims
	claims := map[string]interface{}{
		"eventId":             eventID,
		"queueToken":          "demo-queue-token-sidang",
		"bookingTtlExpiresAt": expiresAt.Unix(),
		"exp":                 expiresAt.Unix(),
		"iat":                 now.Unix(),
	}
	cb, _ := json.Marshal(claims)

	// Sign
	unsigned := b64(hb) + "." + b64(cb)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(unsigned))
	sig := b64(mac.Sum(nil))

	token := unsigned + "." + sig

	fmt.Printf("export ACCESS_TOKEN=\"%s\"\n", token)
	fmt.Fprintf(os.Stderr, "\n✅ Demo token generated\n")
	fmt.Fprintf(os.Stderr, "   eventId : %s\n", eventID)
	fmt.Fprintf(os.Stderr, "   expires : %s (+30 menit)\n", expiresAt.Format("15:04:05 WIB"))
	fmt.Fprintf(os.Stderr, "\nUsage:\n")
	fmt.Fprintf(os.Stderr, "   source <(go run gen_demo_token.go)\n")
	fmt.Fprintf(os.Stderr, "   curl -H \"X-Access-Token: $ACCESS_TOKEN\" http://localhost:8081/api/v1/bookings\n\n")
}
