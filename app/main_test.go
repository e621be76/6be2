package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func get(t *testing.T, mux http.Handler, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

func TestEndpoints(t *testing.T) {
	mux := newMux(100 * time.Millisecond)

	if c := get(t, mux, "/healthz").Code; c != 200 {
		t.Fatalf("healthz = %d", c)
	}

	ready.Store(false)
	if c := get(t, mux, "/readyz").Code; c != 503 {
		t.Fatalf("readyz before ready = %d, want 503", c)
	}
	ready.Store(true)
	if c := get(t, mux, "/readyz").Code; c != 200 {
		t.Fatalf("readyz = %d", c)
	}

	start := time.Now()
	rec := get(t, mux, "/api/quote")
	if took := time.Since(start); took < 100*time.Millisecond {
		t.Fatalf("quote took %v, want >= 100ms of CPU work", took)
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || body["quote"] == "" {
		t.Fatalf("bad quote body %q: %v", rec.Body.String(), err)
	}

	m := get(t, mux, "/metrics").Body.String()
	if !strings.Contains(m, `quote_api_http_requests_total{path="/api/quote",code="200"} 1`) {
		t.Fatalf("counter missing from metrics:\n%s", m)
	}

	if c := get(t, mux, "/nope").Code; c != 404 {
		t.Fatalf("unknown path = %d", c)
	}
}
