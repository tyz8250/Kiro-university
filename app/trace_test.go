package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHealthEndpointReturns200(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("X-Trace-ID", "example-trace-id")
	recorder := httptest.NewRecorder()

	TraceIDMiddleware(http.HandlerFunc(HealthHandler)).ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status code = %d, want %d", recorder.Code, http.StatusOK)
	}
}

func TestEmptyTraceIDReturns400(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("X-Trace-ID", "")
	recorder := httptest.NewRecorder()

	TraceIDMiddleware(http.HandlerFunc(HealthHandler)).ServeHTTP(recorder, req)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status code = %d, want %d", recorder.Code, http.StatusBadRequest)
	}

	var response map[string]string
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode response body: %v", err)
	}
	if response["error"] != "trace_id must not be empty" {
		t.Fatalf("error = %q, want %q",
			response["error"],
			"trace_id must not be empty",
		)
	}
}

func TestLogEntryContainsRequiredFields(t *testing.T) {
	entry := LogEntry{
		Timestamp:  time.Date(2026, time.September, 28, 12, 0, 0, 0, time.UTC),
		TraceID:    TraceID("example-trace-id"),
		Method:     http.MethodGet,
		Path:       "/health",
		Status:     http.StatusOK,
		DurationMs: 1,
	}

	var output bytes.Buffer
	WriteLog(&output, entry)

	var fields map[string]json.RawMessage
	if err := json.Unmarshal(output.Bytes(), &fields); err != nil {
		t.Fatalf("decode log entry: %v", err)
	}

	requiredFields := []string{
		"timestamp",
		"trace_id",
		"method",
		"path",
		"status",
		"duration_ms",
	}
	for _, field := range requiredFields {
		if _, ok := fields[field]; !ok {
			t.Errorf("log entry is missing required field %q", field)
		}
	}
}
