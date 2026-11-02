package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"log"
	"math/rand/v2" // nosemgrep: math-random-used -- picks a quote, not a secret
	"net/http"
	"os"
	"os/signal"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

var quotes = []string{
	"The best way out is always through. - Robert Frost",
	"Simplicity is prerequisite for reliability. - Edsger Dijkstra",
	"It always seems impossible until it's done. - Nelson Mandela",
	"Well done is better than well said. - Benjamin Franklin",
	"Hope is not a strategy. - SRE proverb",
}

// counter is a tiny Prometheus counter vector keyed by label string, no client lib needed
type counter struct {
	mu sync.Mutex
	v  map[string]uint64
}

func (c *counter) inc(labels string) {
	c.mu.Lock()
	c.v[labels]++
	c.mu.Unlock()
}

func (c *counter) write(w http.ResponseWriter, name, help string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	fmt.Fprintf(w, "# HELP %s %s\n# TYPE %s counter\n", name, help, name)
	keys := make([]string, 0, len(c.v))
	for k := range c.v {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		fmt.Fprintf(w, "%s{%s} %d\n", name, k, c.v[k])
	}
}

var (
	requests = &counter{v: map[string]uint64{}}
	ready    atomic.Bool
)

// burnCPU spins for d of wall time so each request costs real CPU
func burnCPU(d time.Duration) {
	sum := sha256.Sum256(nil)
	for end := time.Now().Add(d); time.Now().Before(end); {
		sum = sha256.Sum256(sum[:])
	}
}

type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.code = code
	r.ResponseWriter.WriteHeader(code)
}

func instrument(path string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{ResponseWriter: w, code: http.StatusOK}
		h(rec, r)
		requests.inc(fmt.Sprintf(`path=%q,code="%d"`, path, rec.code))
	}
}

func newMux(work time.Duration) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !ready.Load() {
			http.Error(w, "not ready", http.StatusServiceUnavailable)
			return
		}
		fmt.Fprintln(w, "ready")
	})
	mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		requests.write(w, "quote_api_http_requests_total", "HTTP requests by path and status code.")
	})
	mux.HandleFunc("GET /api/quote", instrument("/api/quote", func(w http.ResponseWriter, _ *http.Request) {
		burnCPU(work)
		w.Header().Set("Content-Type", "application/json")
		host, _ := os.Hostname()
		json.NewEncoder(w).Encode(map[string]string{"quote": quotes[rand.IntN(len(quotes))], "pod": host})
	}))
	return mux
}

func main() {
	addr := ":" + envOr("PORT", "8080")
	work, err := time.ParseDuration(envOr("CPU_WORK", "100ms"))
	if err != nil {
		log.Fatalf("bad CPU_WORK: %v", err)
	}
	srv := &http.Server{Addr: addr, Handler: newMux(work), ReadHeaderTimeout: 5 * time.Second}

	go func() {
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()
	ready.Store(true)
	log.Printf("listening on %s", addr)

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	<-stop
	// fail readiness first so endpoints/ingress drop us before connections close (zero-downtime drain)
	ready.Store(false)
	time.Sleep(parseOr(envOr("SHUTDOWN_DELAY", "5s"), 5*time.Second))
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}

func envOr(k, def string) string {
	if v := strings.TrimSpace(os.Getenv(k)); v != "" {
		return v
	}
	return def
}

func parseOr(s string, def time.Duration) time.Duration {
	if d, err := time.ParseDuration(s); err == nil {
		return d
	}
	return def
}
