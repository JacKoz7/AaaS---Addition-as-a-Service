// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       gateway
// Module:          tests/gateway_test.go
// Owning Team:     Platform Enablement Guild (PEG)
// Classification:  INTERNAL
// Purpose:         Integration tests of the gateway: start the Traefik binary
//                  with the real static and dynamic configuration and the
//                  edge plugin, point the AAAS_UPSTREAM_* variables at stub
//                  upstreams and check routing, error format, timeouts,
//                  health and metrics.
// Related Docs:    services/gateway/config/, services/gateway/docs/API.md,
//                  ADR-0012

package tests

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// publicURL is the public entry point of the gateway inside the test stage.
//
// Description:
//
//	config/traefik.yml binds the `web` entry point to :8000.
//
// Business Justification:
//
//	The tests address the gateway exactly as Compose does (host port 80
//	maps to container port 8000).
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	http.Get(publicURL + "/")
//
// See Also: internalURL.
const publicURL = "http://127.0.0.1:8000"

// internalURL is the internal entry point (health, metrics).
//
// Description:
//
//	config/traefik.yml binds the `internal` entry point to :8080.
//
// Business Justification:
//
//	CLAUDE.md 6.1 puts /health and /metrics on port 8080.
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	http.Get(internalURL + "/health")
//
// See Also: publicURL.
const internalURL = "http://127.0.0.1:8080"

// keysStub plays expression-assembler for POST /api/v1/keys.
//
// Description:
//
//	Answers 202 {"taskId":"t-1"} and echoes the Idempotency-Key and
//	traceparent request headers. The query parameter `status=500` returns a
//	plain-text error, `status=409` an upstream problem document, and
//	`sleep=3s` delays the response past the gateway's header timeout.
//
// Business Justification:
//
//	Lets one upstream exercise every response class the gateway handles.
//
// Parameters:
//   - w: response writer.
//   - r: request received through the gateway.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	None.
//
// Side Effects:
//
//	May sleep for the requested duration.
//
// Complexity: O(1).
// Thread Safety: safe for concurrent use.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	httptest.NewServer(http.HandlerFunc(keysStub))
//
// See Also: TestGateway.
func keysStub(w http.ResponseWriter, r *http.Request) {
	if d, err := time.ParseDuration(r.URL.Query().Get("sleep")); err == nil {
		time.Sleep(d)
	}
	w.Header().Set("X-Seen-Path", r.URL.Path)
	w.Header().Set("X-Seen-Idempotency-Key", r.Header.Get("Idempotency-Key"))
	w.Header().Set("X-Seen-Traceparent", r.Header.Get("traceparent"))
	switch r.URL.Query().Get("status") {
	case "500":
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = io.WriteString(w, "stack trace that must not leak")
	case "409":
		w.Header().Set("Content-Type", "application/problem+json")
		w.WriteHeader(http.StatusConflict)
		_, _ = io.WriteString(w, `{"type":"about:blank","title":"Conflict","status":409,"detail":"seq already used"}`)
	default:
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		_, _ = io.WriteString(w, `{"taskId":"t-1"}`)
	}
}

// tasksStub plays the task status owner for GET /api/v1/tasks/{taskId}.
//
// Description:
//
//	Answers 200 with a JSON document naming the requested path.
//
// Business Justification:
//
//	Verifies that the path reaches the upstream unchanged.
//
// Parameters:
//   - w: response writer.
//   - r: request received through the gateway.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	None.
//
// Side Effects:
//
//	None.
//
// Complexity: O(1).
// Thread Safety: safe for concurrent use.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	httptest.NewServer(http.HandlerFunc(tasksStub))
//
// See Also: TestGateway.
func tasksStub(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"path": r.URL.Path, "status": "COUNTING"})
}

// frontendStub plays frontend-shell for every other path.
//
// Description:
//
//	Answers 200 text/html with the requested path in the body.
//
// Business Justification:
//
//	Verifies the catch-all frontend route.
//
// Parameters:
//   - w: response writer.
//   - r: request received through the gateway.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	None.
//
// Side Effects:
//
//	None.
//
// Complexity: O(len(path)).
// Thread Safety: safe for concurrent use.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	httptest.NewServer(http.HandlerFunc(frontendStub))
//
// See Also: TestGateway.
func frontendStub(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html")
	_, _ = io.WriteString(w, "<html>shell "+r.URL.Path+"</html>")
}

// startTraefik runs the Traefik binary with the gateway configuration.
//
// Description:
//
//	Starts $TRAEFIK_BIN in / (where ./plugins-local is), with the given
//	extra environment, waits up to 20 s for GET /health to answer 200 and
//	registers a cleanup that stops the process. Traefik's output goes to
//	the test log on failure.
//
// Business Justification:
//
//	Tests the configuration that ships in the image, not a copy of it.
//
// Parameters:
//   - t:   the running test.
//   - bin: path of the Traefik binary.
//   - env: extra KEY=VALUE environment entries.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	Fails the test when Traefik cannot start or never becomes healthy.
//
// Side Effects:
//
//	Starts a process listening on :8000 and :8080.
//
// Complexity: O(1) besides the wait.
// Thread Safety: not safe for concurrent use (fixed ports).
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	startTraefik(t, "/usr/local/bin/traefik", []string{"AAAS_UPSTREAM_TASKS=http://127.0.0.1:1"})
//
// See Also: TestGateway.
func startTraefik(t *testing.T, bin string, env []string) {
	t.Helper()
	var output strings.Builder
	cmd := exec.Command(bin, "--configFile=/etc/traefik/traefik.yml")
	cmd.Dir = "/"
	cmd.Env = append(os.Environ(), env...)
	cmd.Stdout = &output
	cmd.Stderr = &output
	if err := cmd.Start(); err != nil {
		t.Fatalf("start traefik: %v", err)
	}
	t.Cleanup(func() {
		_ = cmd.Process.Signal(os.Interrupt)
		_ = cmd.Wait()
		if t.Failed() {
			t.Logf("traefik output:\n%s", output.String())
		}
	})
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		resp, err := http.Get(internalURL + "/health")
		if err == nil {
			_ = resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return
			}
		}
		time.Sleep(200 * time.Millisecond)
	}
	t.Fatalf("traefik not healthy after 20 s")
}

// call sends one request to the gateway and returns status, headers, body.
//
// Description:
//
//	Uses a client with a 15 s timeout, enough for the retried timeout case.
//
// Business Justification:
//
//	Shared request plumbing of the integration tests.
//
// Parameters:
//   - t:       the running test.
//   - method:  HTTP method.
//   - url:     absolute URL.
//   - headers: request headers, may be nil.
//
// Returns:
//   - int:         status code.
//   - http.Header: response headers.
//   - string:      response body.
//
// Errors:
//
//	Fails the test on a transport error.
//
// Side Effects:
//
//	One HTTP request.
//
// Complexity: O(body size).
// Thread Safety: safe for concurrent use.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	status, _, body := call(t, http.MethodGet, publicURL+"/", nil)
//
// See Also: TestGateway.
func call(t *testing.T, method, url string, headers map[string]string) (int, http.Header, string) {
	t.Helper()
	req, err := http.NewRequest(method, url, nil)
	if err != nil {
		t.Fatalf("request %s %s: %v", method, url, err)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := (&http.Client{Timeout: 15 * time.Second}).Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, url, err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, resp.Header, string(body)
}

// expectProblem asserts an RFC 9457 response with the given status.
//
// Description:
//
//	Checks the media type and that the JSON body repeats the status and
//	names the request path as instance.
//
// Business Justification:
//
//	One definition of a valid gateway error for the integration tests.
//
// Parameters:
//   - t:        the running test.
//   - status:   the received status code.
//   - header:   the received headers.
//   - body:     the received body.
//   - want:     the expected status code.
//   - instance: the expected request path.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	Fails the test on any mismatch.
//
// Side Effects:
//
//	None.
//
// Complexity: O(body size).
// Thread Safety: safe for concurrent use.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	expectProblem(t, status, header, body, 404, "/api/x")
//
// See Also: problemDoc.
func expectProblem(t *testing.T, status int, header http.Header, body string, want int, instance string) {
	t.Helper()
	if status != want || header.Get("Content-Type") != "application/problem+json" {
		t.Fatalf("got %d %q %q, want a %d problem", status, header.Get("Content-Type"), body, want)
	}
	var p problemDoc
	if err := json.Unmarshal([]byte(body), &p); err != nil || p.Status != want || p.Instance != instance {
		t.Fatalf("problem %q (err %v), want status %d instance %s", body, err, want, instance)
	}
}

// TestGateway runs the gateway against stub upstreams.
//
// Description:
//
//	Skipped unless TRAEFIK_BIN is set (it is in the Dockerfile `test`
//	stage). Subtests run in order on one Traefik process; the last one
//	stops the tasks upstream to observe a 502.
//
// Business Justification:
//
//	Proves the routes of CLAUDE.md 4.1 that exist in Phase 1, the RFC 9457
//	error format at the edge, the timeouts of CLAUDE.md 6.1 and the health
//	and metrics endpoints.
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
//	Fails the test on any routing or format regression.
//
// Side Effects:
//
//	Starts Traefik and three local HTTP servers.
//
// Complexity: O(1); about 10 s of wall time (the timeout case).
// Thread Safety: not safe for parallel runs (fixed ports).
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	TRAEFIK_BIN=/usr/local/bin/traefik go test -run TestGateway -v
//
// See Also: startTraefik, config/dynamic/routes.yml.
func TestGateway(t *testing.T) {
	bin := os.Getenv("TRAEFIK_BIN")
	if bin == "" {
		t.Skip("TRAEFIK_BIN not set; the integration test runs in the Dockerfile test stage")
	}
	keys := httptest.NewServer(http.HandlerFunc(keysStub))
	defer keys.Close()
	tasks := httptest.NewServer(http.HandlerFunc(tasksStub))
	defer tasks.Close()
	frontend := httptest.NewServer(http.HandlerFunc(frontendStub))
	defer frontend.Close()
	startTraefik(t, bin, []string{
		"AAAS_UPSTREAM_EXPRESSION_ASSEMBLER=" + keys.URL,
		"AAAS_UPSTREAM_TASKS=" + tasks.URL,
		"AAAS_UPSTREAM_FRONTEND=" + frontend.URL,
	})

	t.Run("keys route forwards to expression-assembler with headers", func(t *testing.T) {
		status, header, body := call(t, http.MethodPost, publicURL+"/api/v1/keys", map[string]string{
			"Idempotency-Key": "k-42",
			"traceparent":     "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
		})
		if status != http.StatusAccepted || body != `{"taskId":"t-1"}` {
			t.Fatalf("got %d %q, want 202 from the stub", status, body)
		}
		if header.Get("X-Seen-Idempotency-Key") != "k-42" || !strings.HasPrefix(header.Get("X-Seen-Traceparent"), "00-4bf92f") {
			t.Fatalf("headers not forwarded: %v", header)
		}
	})
	t.Run("upstream plain error becomes a problem", func(t *testing.T) {
		status, header, body := call(t, http.MethodPost, publicURL+"/api/v1/keys?status=500", nil)
		expectProblem(t, status, header, body, http.StatusInternalServerError, "/api/v1/keys")
		if strings.Contains(body, "stack trace") {
			t.Fatalf("upstream body leaked: %q", body)
		}
	})
	t.Run("upstream problem passes through", func(t *testing.T) {
		status, _, body := call(t, http.MethodPost, publicURL+"/api/v1/keys?status=409", nil)
		if status != http.StatusConflict || !strings.Contains(body, "seq already used") {
			t.Fatalf("got %d %q, want the upstream 409 problem", status, body)
		}
	})
	t.Run("slow upstream becomes a 504 problem", func(t *testing.T) {
		status, header, body := call(t, http.MethodPost, publicURL+"/api/v1/keys?sleep=3s", nil)
		expectProblem(t, status, header, body, http.StatusGatewayTimeout, "/api/v1/keys")
	})
	t.Run("task route forwards the task path", func(t *testing.T) {
		status, _, body := call(t, http.MethodGet, publicURL+"/api/v1/tasks/018f3c2e", nil)
		if status != http.StatusOK || !strings.Contains(body, `"/api/v1/tasks/018f3c2e"`) {
			t.Fatalf("got %d %q", status, body)
		}
	})
	t.Run("unknown api paths are 404 problems", func(t *testing.T) {
		for _, path := range []string{"/api", "/api/v1/tasks/018f3c2e/unknown", "/api/v1/nothing"} {
			status, header, body := call(t, http.MethodGet, publicURL+path, nil)
			expectProblem(t, status, header, body, http.StatusNotFound, path)
		}
	})
	t.Run("everything else goes to the frontend", func(t *testing.T) {
		for _, path := range []string{"/", "/index.html", "/apiary"} {
			status, header, body := call(t, http.MethodGet, publicURL+path, nil)
			if status != http.StatusOK || header.Get("Content-Type") != "text/html" || body != "<html>shell "+path+"</html>" {
				t.Fatalf("%s: got %d %q", path, status, body)
			}
		}
	})
	t.Run("health and metrics on the internal entry point", func(t *testing.T) {
		status, header, body := call(t, http.MethodGet, internalURL+"/health", nil)
		if status != http.StatusOK || header.Get("Content-Type") != "application/json" || !strings.Contains(body, `"status":"ok"`) {
			t.Fatalf("health: %d %q", status, body)
		}
		status, _, body = call(t, http.MethodGet, internalURL+"/metrics", nil)
		if status != http.StatusOK || !strings.Contains(body, `traefik_router_requests_total{`) ||
			!strings.Contains(body, `router="api-keys@file"`) {
			t.Fatalf("metrics: %d, router metrics missing", status)
		}
		status, _, _ = call(t, http.MethodGet, publicURL+"/health", nil)
		if status != http.StatusOK {
			t.Fatalf("public /health should reach the frontend stub, got %d", status)
		}
	})
	t.Run("unreachable upstream becomes a 502 problem", func(t *testing.T) {
		tasks.Close()
		status, header, body := call(t, http.MethodGet, publicURL+"/api/v1/tasks/018f3c2e", nil)
		expectProblem(t, status, header, body, http.StatusBadGateway, "/api/v1/tasks/018f3c2e")
	})
}
