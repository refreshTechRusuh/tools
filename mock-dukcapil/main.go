// mock-dukcapil — Mock service Dukcapil untuk lokal dev (tanpa BE-1).
// Validasi NIK harus ada di daftar penduduk DAN semua field harus cocok persis.
// NIK yang tidak terdaftar atau field tidak cocok -> valid:false.
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

type penduduk struct {
	NIK      string
	Nama     string
	TglLahir string
	NamaIbu  string
}

// dataPenduduk adalah daftar NIK yang terdaftar di mock Dukcapil.
// Semua field harus cocok persis (case-sensitive) untuk return valid:true.
var dataPenduduk = []penduduk{
	{
		NIK:      "3273000000000001",
		Nama:     "Budi Santoso",
		TglLahir: "1992-05-10",
		NamaIbu:  "Siti Rahayu",
	},
	{
		NIK:      "3273000000000002",
		Nama:     "Ani Wulandari",
		TglLahir: "1995-08-22",
		NamaIbu:  "Dewi Kusuma",
	},
}

// nikIndex adalah lookup map untuk performa O(1).
var nikIndex map[string]penduduk

func init() {
	nikIndex = make(map[string]penduduk, len(dataPenduduk))
	for _, p := range dataPenduduk {
		nikIndex[p.NIK] = p
	}
}

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

	// POST /api/dukcapil/v1/verify
	mux.HandleFunc("POST /api/dukcapil/v1/verify", func(w http.ResponseWriter, r *http.Request) {
		var req verifyRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, `{"status":"400","message":"invalid body"}`, http.StatusBadRequest)
			return
		}

		var valid bool
		var reason string

		p, found := nikIndex[req.NIK]
		if !found {
			valid = false
			reason = "NIK tidak terdaftar"
		} else if req.Nama != p.Nama {
			valid = false
			reason = "nama tidak cocok"
		} else if req.TglLahir != p.TglLahir {
			valid = false
			reason = "tglLahir tidak cocok"
		} else if req.NamaIbu != p.NamaIbu {
			valid = false
			reason = "namaIbu tidak cocok"
		} else {
			valid = true
		}

		if valid {
			log.Printf("[dukcapil-mock] VALID   nik=%s*** nama=%q\n", req.NIK[:4], req.Nama)
		} else {
			log.Printf("[dukcapil-mock] INVALID nik=%s*** reason=%q\n", func() string {
				if len(req.NIK) >= 4 {
					return req.NIK[:4]
				}
				return req.NIK
			}(), reason)
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
	log.Println("   POST /api/dukcapil/v1/verify  → lookup NIK + validasi semua field")
	log.Println("   GET  /sys/ping                → health check")
	log.Printf("   %d NIK terdaftar: ", len(dataPenduduk))
	for _, p := range dataPenduduk {
		log.Printf("     - %s (%s)\n", p.NIK, p.Nama)
	}
	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
