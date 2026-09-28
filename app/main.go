package main

import (
	"log"
	"net/http"
)

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", HealthHandler)

	handler := TraceIDMiddleware(mux)

	log.Println("server listening on :8080")

	if err := http.ListenAndServe(":8080", handler); err != nil {
		log.Fatal(err)
	}
}
