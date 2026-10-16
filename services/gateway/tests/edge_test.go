// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       gateway
// Module:          tests/edge_test.go
// Owning Team:     Platform Enablement Guild (PEG)
// Classification:  INTERNAL
// Purpose:         Unit tests of the edge plugin through its public entry
//                  points (CreateConfig, New), with in-memory upstreams.
// Related Docs:    services/gateway/src/edge/edge.go, ADR-0012

// Package tests holds the unit and integration tests of the gateway.
//
// Description:
//
//	edge_test.go exercises the edge plugin in-process; gateway_test.go runs
//	the Traefik binary with the gateway configuration (only when
//	TRAEFIK_BIN is set, as in the Dockerfile `test` stage).
//
// Business Justification:
//
//	The gateway is the only entry point of AaaS; a routing or error-format
//	regression breaks every addition.
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// See Also: services/gateway/Dockerfile (test stage).
package tests

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"aaas/edge"
)

// problemDoc mirrors the RFC 9457 members the gateway writes.
//
// Description:
//
//	Decoding target for assertions on problem responses.
//
// Business Justification:
//
//	Lets the tests check every member instead of comparing raw strings.
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	var p problemDoc
//	_ = json.Unmarshal(body, &p)
//
// See Also: decodeProblem.
type problemDoc struct {
	// Type is the problem type URI.
	Type string `json:"type"`
	// Title is the reason phrase.
	Title string `json:"title"`
	// Status is the HTTP status code.
	Status int `json:"status"`
	// Detail is the optional explanation.
	Detail string `json:"detail"`
	// Instance is the request path.
	Instance string `json:"instance"`
}

// newHandler builds an edge middleware or fails the test.
//
// Description:
//
//	Calls edge.New with the given mode and next handler.
//
// Business Justification:
//
//	Keeps every test focused on behaviour rather than construction.
//
// Parameters:
//   - t:    the running test.
//   - mode: an edge mode constant.
//   - next: the upstream handler, may be nil for the responding modes.
//
// Returns:
//   - http.Handler: the middleware.
//
// Errors:
//
//	Fails the test when edge.New returns an error.
//
// Side Effects:
//
//	None.
//
// Complexity: O(1) time and memory.
// Thread Safety: safe for concurrent use.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	h := newHandler(t, edge.ModeHealth, nil)
//
// See Also: edge.New.
func newHandler(t *testing.T, mode string, next http.Handler) http.Handler {
	t.Helper()
	h, err := edge.New(context.Background(), next, &edge.Config{Mode: mode}, "test")
	if err != nil {
		t.Fatalf("edge.New(%q): %v", mode, err)
	}
	return h
}

// serve runs one request through a handler and returns the recorder.
//
// Description:
//
//	Uses httptest.NewRecorder, which implements http.Flusher.
//
// Business Justification:
//
//	Shared request plumbing of the unit tests.
//
// Parameters:
//   - h:      handler under test.
//   - method: HTTP method.
//   - target: request path.
//
// Returns:
//   - *httptest.ResponseRecorder: the recorded response.
//
// Errors:
//
//	None.
//
// Side Effects:
//
//	None (in-memory).
//
// Complexity: O(response size) time and memory.
// Thread Safety: safe for concurrent use with distinct handlers.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	rec := serve(h, http.MethodGet, "/api/v1/keys")
//
// See Also: newHandler.
func serve(h http.Handler, method, target string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, target, nil))
	return rec
}

// decodeProblem asserts a problem response and decodes it.
//
// Description:
//
//	Checks status, Content-Type and nosniff, then decodes the body and
//	checks that the status member repeats the HTTP status.
//
// Business Justification:
//
//	One definition of "a valid RFC 9457 response" for every test.
//
// Parameters:
//   - t:      the running test.
//   - rec:    the recorded response.
//   - status: the expected HTTP status.
//
// Returns:
//   - problemDoc: the decoded document.
//
// Errors:
//
//	Fails the test on any mismatch or invalid JSON.
//
// Side Effects:
//
//	None.
//
// Complexity: O(body size) time and memory.
// Thread Safety: safe for concurrent use.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	p := decodeProblem(t, rec, http.StatusNotFound)
//
// See Also: problemDoc.
func decodeProblem(t *testing.T, rec *httptest.ResponseRecorder, status int) problemDoc {
	t.Helper()
	if rec.Code != status {
		t.Fatalf("status = %d, want %d (body %q)", rec.Code, status, rec.Body.String())
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/problem+json" {
		t.Fatalf("Content-Type = %q, want application/problem+json", ct)
	}
	if rec.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("X-Content-Type-Options missing")
	}
	var p problemDoc
	if err := json.Unmarshal(rec.Body.Bytes(), &p); err != nil {
		t.Fatalf("body is not JSON: %v (%q)", err, rec.Body.String())
	}
	if p.Status != status || p.Type != "about:blank" || p.Title != http.StatusText(status) {
		t.Fatalf("problem = %+v, want type about:blank, status %d, title %q", p, status, http.StatusText(status))
	}
	return p
}

// TestCreateConfigDefaultsToProblem checks the default mode.
//
// Description:
//
//	CreateConfig must select ModeProblem, so a middleware declared without
//	a mode rewrites errors.
//
// Business Justification:
//
//	A forgotten mode must fail safe (errors still RFC 9457).
//
// Parameters:
//   - t: the running test.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	Fails the test on a different default.
//
// Side Effects:
//
//	None.
//
// Complexity: O(1).
// Thread Safety: safe for parallel tests.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	go test -run TestCreateConfigDefaultsToProblem
//
// See Also: edge.CreateConfig.
func TestCreateConfigDefaultsToProblem(t *testing.T) {
	if got := edge.CreateConfig().Mode; got != edge.ModeProblem {
		t.Fatalf("CreateConfig().Mode = %q, want %q", got, edge.ModeProblem)
	}
}

// TestNewRejectsInvalidConfiguration checks the construction errors.
//
// Description:
//
//	An unknown mode and ModeProblem without a next handler are errors; a
//	nil config falls back to the default.
//
// Business Justification:
//
//	A typo in the dynamic configuration must be reported by Traefik, not
//	silently disable the error format.
//
// Parameters:
//   - t: the running test.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	Fails the test when an invalid configuration is accepted.
//
// Side Effects:
//
//	None.
//
// Complexity: O(1).
// Thread Safety: safe for parallel tests.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	go test -run TestNewRejectsInvalidConfiguration
//
// See Also: edge.New.
func TestNewRejectsInvalidConfiguration(t *testing.T) {
	ctx := context.Background()
	ok := http.HandlerFunc(func(http.ResponseWriter, *http.Request) {})
	if _, err := edge.New(ctx, ok, &edge.Config{Mode: "teapot"}, "bad"); err == nil {
		t.Fatal("unknown mode accepted")
	}
	if _, err := edge.New(ctx, nil, &edge.Config{Mode: edge.ModeProblem}, "bad"); err == nil {
		t.Fatal("problem mode without next handler accepted")
	}
	if _, err := edge.New(ctx, ok, nil, "default"); err != nil {
		t.Fatalf("nil config rejected: %v", err)
	}
}

// TestProblemRewritesPlainErrors checks the rewriting of non-compliant errors.
//
// Description:
//
//	A plain-text 502 (what Traefik writes when an upstream is down) and a
//	JSON 500 from an upstream both become problem documents with the same
//	status; upstream body bytes and Content-Length are dropped.
//
// Business Justification:
//
//	CLAUDE.md 4.1: every API error is RFC 9457.
//
// Parameters:
//   - t: the running test.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	Fails the test when a response is not rewritten.
//
// Side Effects:
//
//	None.
//
// Complexity: O(1).
// Thread Safety: safe for parallel tests.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	go test -run TestProblemRewritesPlainErrors
//
// See Also: edge.ModeProblem.
func TestProblemRewritesPlainErrors(t *testing.T) {
	cases := []struct {
		name, contentType, body, detail string
		status                          int
	}{
		{"traefik bad gateway", "text/plain; charset=utf-8", "upstream body: Bad Gateway", "The upstream service is unavailable.", http.StatusBadGateway},
		{"upstream json error", "application/json", `{"error":"boom"}`, "", http.StatusInternalServerError},
		{"no content type", "", "", "No healthy upstream server is available.", http.StatusServiceUnavailable},
		{"timeout", "text/plain", "upstream body: Gateway Timeout", "The upstream service did not respond in time.", http.StatusGatewayTimeout},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				if c.contentType != "" {
					w.Header().Set("Content-Type", c.contentType)
				}
				w.Header().Set("Content-Length", "999")
				w.WriteHeader(c.status)
				_, _ = w.Write([]byte(c.body))
			})
			rec := serve(newHandler(t, edge.ModeProblem, next), http.MethodPost, "/api/v1/keys")
			p := decodeProblem(t, rec, c.status)
			if p.Detail != c.detail || p.Instance != "/api/v1/keys" {
				t.Fatalf("problem = %+v, want detail %q and instance /api/v1/keys", p, c.detail)
			}
			if c.body != "" && strings.Contains(rec.Body.String(), c.body) {
				t.Fatalf("upstream body leaked: %q", rec.Body.String())
			}
			if rec.Header().Get("Content-Length") == "999" {
				t.Fatal("upstream Content-Length kept")
			}
		})
	}
}

// TestProblemPassesUpstreamProblems checks that compliant errors are untouched.
//
// Description:
//
//	An upstream problem document (with a charset parameter and mixed case)
//	keeps its status, headers and body.
//
// Business Justification:
//
//	Services own the detail of their errors (e.g. validation messages).
//
// Parameters:
//   - t: the running test.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	Fails the test when the upstream document is changed.
//
// Side Effects:
//
//	None.
//
// Complexity: O(1).
// Thread Safety: safe for parallel tests.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	go test -run TestProblemPassesUpstreamProblems
//
// See Also: edge.ModeProblem.
func TestProblemPassesUpstreamProblems(t *testing.T) {
	body := `{"type":"https://aaas.local/problems/out-of-range","title":"Operand out of range","status":422}`
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "Application/Problem+JSON; charset=utf-8")
		w.WriteHeader(http.StatusUnprocessableEntity)
		_, _ = w.Write([]byte(body))
	})
	rec := serve(newHandler(t, edge.ModeProblem, next), http.MethodPost, "/api/v1/keys")
	if rec.Code != http.StatusUnprocessableEntity || rec.Body.String() != body {
		t.Fatalf("got %d %q, want 422 with the upstream body", rec.Code, rec.Body.String())
	}
}

// TestProblemPassesSuccessAndStreams checks success responses and flushing.
//
// Description:
//
//	A 202 with an implicit header (Write before WriteHeader) and a streamed
//	response with Flush pass through unchanged; the flush reaches the
//	client writer.
//
// Business Justification:
//
//	`=` returns 202 { taskId } and the timer uses server-sent events
//	(CLAUDE.md 4.1); neither may be altered or delayed by the gateway.
//
// Parameters:
//   - t: the running test.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	Fails the test when a success response is changed or not flushed.
//
// Side Effects:
//
//	None.
//
// Complexity: O(1).
// Thread Safety: safe for parallel tests.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	go test -run TestProblemPassesSuccessAndStreams
//
// See Also: edge.ModeProblem.
func TestProblemPassesSuccessAndStreams(t *testing.T) {
	accepted := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte(`{"taskId":"t-1"}`))
	})
	rec := serve(newHandler(t, edge.ModeProblem, accepted), http.MethodPost, "/api/v1/keys")
	if rec.Code != http.StatusAccepted || rec.Body.String() != `{"taskId":"t-1"}` {
		t.Fatalf("got %d %q, want 202 with the upstream body", rec.Code, rec.Body.String())
	}

	streamed := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("data: {\"elapsedMs\":100}\n\n"))
		w.(http.Flusher).Flush()
	})
	rec = serve(newHandler(t, edge.ModeProblem, streamed), http.MethodGet, "/api/v1/tasks/t-1/timer")
	if rec.Code != http.StatusOK || !rec.Flushed || !strings.HasPrefix(rec.Body.String(), "data: ") {
		t.Fatalf("got %d flushed=%v %q, want a flushed 200 stream", rec.Code, rec.Flushed, rec.Body.String())
	}
}

// TestNotFoundMode checks the catch-all API answer.
//
// Description:
//
//	Every method gets a 404 problem whose instance is the request path; the
//	next handler is not called. HEAD gets headers without a body.
//
// Business Justification:
//
//	Unknown API paths are API errors (CLAUDE.md 4.1).
//
// Parameters:
//   - t: the running test.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	Fails the test on a wrong response or a call to the next handler.
//
// Side Effects:
//
//	None.
//
// Complexity: O(1).
// Thread Safety: safe for parallel tests.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	go test -run TestNotFoundMode
//
// See Also: edge.ModeNotFound.
func TestNotFoundMode(t *testing.T) {
	called := false
	next := http.HandlerFunc(func(http.ResponseWriter, *http.Request) { called = true })
	h := newHandler(t, edge.ModeNotFound, next)
	p := decodeProblem(t, serve(h, http.MethodDelete, "/api/v2/nothing"), http.StatusNotFound)
	if p.Instance != "/api/v2/nothing" || p.Detail == "" {
		t.Fatalf("problem = %+v", p)
	}
	head := serve(h, http.MethodHead, "/api/v2/nothing")
	if head.Code != http.StatusNotFound || head.Body.Len() != 0 {
		t.Fatalf("HEAD got %d with %d body bytes, want 404 without body", head.Code, head.Body.Len())
	}
	if called {
		t.Fatal("next handler called")
	}
}

// TestHealthMode checks the health document.
//
// Description:
//
//	The response is 200 application/json with status "ok" and a "proxy"
//	check, uncacheable.
//
// Business Justification:
//
//	The Compose health check depends on it (CLAUDE.md 6.1).
//
// Parameters:
//   - t: the running test.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	Fails the test on a different document.
//
// Side Effects:
//
//	None.
//
// Complexity: O(1).
// Thread Safety: safe for parallel tests.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	go test -run TestHealthMode
//
// See Also: edge.ModeHealth.
func TestHealthMode(t *testing.T) {
	rec := serve(newHandler(t, edge.ModeHealth, nil), http.MethodGet, "/health")
	if rec.Code != http.StatusOK || rec.Header().Get("Content-Type") != "application/json" ||
		rec.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("got %d %v", rec.Code, rec.Header())
	}
	var doc struct {
		Status string            `json:"status"`
		Checks map[string]string `json:"checks"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &doc); err != nil || doc.Status != "ok" || doc.Checks["proxy"] != "ok" {
		t.Fatalf("health body %q (err %v)", rec.Body.String(), err)
	}
}
