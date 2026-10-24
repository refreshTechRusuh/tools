// mock-dukcapil — Mock service Dukcapil untuk lokal dev (tanpa BE-1).
// Selalu return valid:true untuk NIK apapun yang format 16 digit.
//
// Run: go run main.go
// Port: 8085 (sesuai DUKCAPIL_BASE_URL di .env)

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
)

type verifyRequest struct {
	NIK      string `json:"nik"`
	Nama     string `json:"nama"`
	TglLahir string `json:"tglLahir"`
	NamaIbu  string `json:"namaIbu"`
}

type verifyResponse struct {
	Status  string `json:"status"`
	Message string `json:"message"`
	Data    struct {
		Valid bool `json:"valid"`
	} `json:"data"`
}

func main() {
	mux := http.NewServeMux()

	// POST /internal/dukcapil/verify
	mux.HandleFunc("POST /internal/dukcapil/verify", func(w http.ResponseWriter, r *http.Request) {
		var req verifyRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, `{"status":"400","message":"invalid body"}`, http.StatusBadRequest)
			return
		}

		valid := len(req.NIK) == 16
		if valid {
			log.Printf("[dukcapil-mock] VALID  nik=%s*** nama=%q\n", req.NIK[:4], req.Nama)
		} else {
			log.Printf("[dukcapil-mock] INVALID nik=%q (bukan 16 digit)\n", req.NIK)
		}

		resp := verifyResponse{Status: "00000", Message: "OK"}
		resp.Data.Valid = valid

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	})

	// GET /sys/ping — health check
	mux.HandleFunc("GET /sys/ping", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"status":"00000","message":"mock-dukcapil ok","data":{}}`)
	})

	srv := &http.Server{
		Addr:              ":8085",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Println("🪪  mock-dukcapil listening on :8085")
	log.Println("   POST /internal/dukcapil/verify  → always valid=true (16-digit NIK)")
	log.Println("   GET  /sys/ping                  → health check")
	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
