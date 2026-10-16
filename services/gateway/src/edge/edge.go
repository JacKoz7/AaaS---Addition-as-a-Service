// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       gateway
// Module:          edge
// Owning Team:     Platform Enablement Guild (PEG)
// Classification:  INTERNAL
// Purpose:         Traefik middleware plugin of the gateway: rewrites every
//                  API error response that is not already RFC 9457 problem
//                  details into application/problem+json, answers unknown
//                  API paths with a 404 problem, and serves the JSON health
//                  endpoint.
// Related Docs:    services/gateway/README.md, services/gateway/docs/API.md,
//                  ADR-0012, CLAUDE.md (4.1, 6.1)

// Package edge is the Traefik middleware plugin of the AaaS gateway.
//
// Description:
//
//	Traefik loads the package from /plugins-local/src/aaas/edge and runs
//	it in its embedded Go interpreter (Yaegi), so the package uses the
//	standard library only. One middleware type serves three purposes,
//	selected by Config.Mode:
//
//	  - "problem": wraps the upstream service. A response with status 400
//	    or higher whose Content-Type is not application/problem+json is
//	    replaced by an RFC 9457 problem document with the same status. This
//	    covers the errors Traefik itself generates (502 when an upstream
//	    does not answer, 503 when no server is available, 504 on a timeout)
//	    and any non-compliant upstream error. Problem documents produced by
//	    upstream services, and every response below 400, pass through
//	    unchanged, including streamed responses.
//	  - "not-found": answers every request with a 404 problem without
//	    calling the next handler; used by the catch-all API router.
//	  - "health": answers every request with the health document of
//	    CLAUDE.md 6.1 without calling the next handler.
//
// Business Justification:
//
//	CLAUDE.md 4.1 requires every API error to be RFC 9457 problem details,
//	including the errors raised before a request reaches an AaaS service,
//	and CLAUDE.md 6.1 requires a JSON health endpoint on port 8080. Traefik
//	offers neither natively; this plugin closes the gap without adding a
//	container to the request path.
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// See Also: ADR-0012, services/gateway/config/dynamic/routes.yml.
package edge

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

// ModeProblem rewrites non-compliant error responses of the next handler.
//
// Description:
//
//	Value of Config.Mode that wraps the upstream service; see the package
//	documentation for the rewriting rules.
//
// Business Justification:
//
//	Guarantees RFC 9457 errors on every API route (CLAUDE.md 4.1).
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	cfg := &Config{Mode: ModeProblem}
//
// See Also: Config, ModeNotFound, ModeHealth.
const ModeProblem = "problem"

// ModeNotFound answers every request with a 404 problem document.
//
// Description:
//
//	Value of Config.Mode for the catch-all router of /api: a path that no
//	API route matches gets a 404 problem instead of Traefik's plain-text
//	"404 page not found". The next handler is never called.
//
// Business Justification:
//
//	Unknown API paths are API errors and must be RFC 9457 (CLAUDE.md 4.1).
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	cfg := &Config{Mode: ModeNotFound}
//
// See Also: Config, ModeProblem.
const ModeNotFound = "not-found"

// ModeHealth answers every request with the health document.
//
// Description:
//
//	Value of Config.Mode for the /health router of the internal entry
//	point: the response is 200 with {"status":"ok","checks":{"proxy":"ok"}}.
//	Reaching the handler proves that Traefik accepted the connection,
//	loaded the dynamic configuration (the router exists) and runs the
//	plugin, which is what the "proxy" check reports. The next handler is
//	never called.
//
// Business Justification:
//
//	CLAUDE.md 6.1 requires GET /health with a JSON {status, checks} body on
//	port 8080 for the Compose health check.
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	cfg := &Config{Mode: ModeHealth}
//
// See Also: Config, healthBody.
const ModeHealth = "health"

// problemContentType is the media type of RFC 9457 problem documents.
//
// Description:
//
//	Compared case-insensitively, ignoring parameters such as charset, by
//	isProblem; written verbatim by writeProblem.
//
// Business Justification:
//
//	CLAUDE.md 4.1 names application/problem+json as the error format.
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	w.Header().Set("Content-Type", problemContentType)
//
// See Also: isProblem, writeProblem.
const problemContentType = "application/problem+json"

// healthBody is the response body of the health endpoint.
//
// Description:
//
//	Fixed JSON document in the shape of CLAUDE.md 6.1; see ModeHealth for
//	what the single "proxy" check means.
//
// Business Justification:
//
//	The Compose health check and operators read the same document on every
//	service.
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	_, _ = w.Write([]byte(healthBody))
//
// See Also: ModeHealth.
const healthBody = `{"status":"ok","checks":{"proxy":"ok"}}` + "\n"

// Config is the configuration of one edge middleware instance.
//
// Description:
//
//	Traefik decodes the `plugin.edge` block of a middleware in the dynamic
//	configuration into this struct. Mode selects the behaviour; an empty
//	Mode means ModeProblem.
//
// Business Justification:
//
//	One plugin with three modes keeps the gateway to a single local plugin
//	that Traefik loads and the tests exercise.
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	middlewares:
//	  api-problem:
//	    plugin:
//	      edge:
//	        mode: problem
//
// See Also: CreateConfig, New.
type Config struct {
	// Mode is one of ModeProblem, ModeNotFound or ModeHealth.
	Mode string `json:"mode,omitempty"`
}

// CreateConfig returns the default configuration of the plugin.
//
// Description:
//
//	Called by Traefik before decoding the dynamic configuration into the
//	result; the default Mode is ModeProblem.
//
// Business Justification:
//
//	Required entry point of a Traefik middleware plugin.
//
// Parameters:
//
//	None.
//
// Returns:
//   - *Config: a new configuration with Mode set to ModeProblem.
//
// Errors:
//
//	None.
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
//	cfg := CreateConfig() // cfg.Mode == "problem"
//
// See Also: Config, New.
func CreateConfig() *Config {
	return &Config{Mode: ModeProblem}
}

// New creates the middleware handler for one configured instance.
//
// Description:
//
//	Validates config.Mode and returns the handler of that mode. The
//	returned handler keeps no state between requests.
//
// Business Justification:
//
//	Required entry point of a Traefik middleware plugin.
//
// Parameters:
//   - ctx:    context of the Traefik configuration load; unused.
//   - next:   the next handler in the chain (the upstream service); must
//     not be nil for ModeProblem.
//   - config: the decoded configuration; nil means CreateConfig().
//   - name:   the middleware name, quoted in error messages.
//
// Returns:
//   - http.Handler: the middleware of the configured mode.
//
// Errors:
//   - an error when config.Mode is not one of the three modes, or when
//     next is nil in ModeProblem; Traefik then reports the middleware as
//     invalid and the routers that use it return 500 until fixed.
//
// Side Effects:
//
//	None at creation time.
//
// Complexity: O(1) time and memory.
// Thread Safety: safe for concurrent use; the handler is stateless.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	h, err := New(ctx, upstream, &Config{Mode: ModeProblem}, "api-problem")
//
// See Also: Config, problemHandler, respondHandler.
func New(ctx context.Context, next http.Handler, config *Config, name string) (http.Handler, error) {
	_ = ctx
	if config == nil {
		config = CreateConfig()
	}
	switch config.Mode {
	case "", ModeProblem:
		if next == nil {
			return nil, fmt.Errorf("edge middleware %q: mode %q needs a next handler", name, ModeProblem)
		}
		return &problemHandler{next: next}, nil
	case ModeNotFound:
		return &respondHandler{health: false}, nil
	case ModeHealth:
		return &respondHandler{health: true}, nil
	default:
		return nil, fmt.Errorf("edge middleware %q: unknown mode %q (want %q, %q or %q)",
			name, config.Mode, ModeProblem, ModeNotFound, ModeHealth)
	}
}

// problemHandler is the handler of ModeProblem.
//
// Description:
//
//	Calls the next handler with a problemWriter that rewrites
//	non-compliant error responses.
//
// Business Justification:
//
//	Enforces RFC 9457 at the single entry point of AaaS (CLAUDE.md 4.1).
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	h := &problemHandler{next: upstream}
//
// See Also: problemWriter, New.
type problemHandler struct {
	// next is the upstream handler whose responses are inspected.
	next http.Handler
}

// ServeHTTP passes the request to the next handler through a problemWriter.
//
// Description:
//
//	The request is forwarded unchanged; only the response may be rewritten.
//
// Business Justification:
//
//	See problemHandler.
//
// Parameters:
//   - rw:  the client response writer.
//   - req: the client request.
//
// Returns:
//
//	Nothing; the response is written to rw.
//
// Errors:
//
//	None of its own; upstream failures arrive as error statuses and are
//	rewritten.
//
// Side Effects:
//
//	Proxies the request to the upstream service (network I/O by Traefik).
//
// Complexity: O(1) time and memory besides the proxied response, which is
// streamed, not buffered.
// Thread Safety: safe for concurrent use.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	h.ServeHTTP(rw, req)
//
// See Also: problemWriter.WriteHeader.
func (h *problemHandler) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	h.next.ServeHTTP(&problemWriter{ResponseWriter: rw, req: req}, req)
}

// problemWriter is the response writer that rewrites error responses.
//
// Description:
//
//	Decides at WriteHeader time: a status of 400 or more without a problem
//	Content-Type is replaced by a problem document and the upstream body is
//	discarded; anything else is passed through. Flush is forwarded so that
//	streamed responses (server-sent events) are not delayed.
//
// Business Justification:
//
//	See problemHandler.
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	w := &problemWriter{ResponseWriter: rw, req: req}
//
// See Also: problemHandler, writeProblem.
type problemWriter struct {
	// ResponseWriter is the client response writer being wrapped.
	http.ResponseWriter
	// req is the client request, used for the problem `instance` member.
	req *http.Request
	// wroteHeader records that the status line was decided.
	wroteHeader bool
	// replaced records that the response was replaced by a problem document
	// and that upstream body bytes must be discarded.
	replaced bool
}

// WriteHeader passes the status through or replaces the response.
//
// Description:
//
//	Only the first call has an effect, as with net/http. For a status of
//	400 or more whose Content-Type is not application/problem+json, the
//	upstream headers that describe the body (Content-Length,
//	Content-Encoding, Content-Range, ETag) are removed and a problem
//	document is written instead.
//
// Business Justification:
//
//	See problemHandler.
//
// Parameters:
//   - code: HTTP status code chosen by the upstream or by Traefik, 100–599.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	None; write errors of the client connection are ignored, as net/http
//	does for WriteHeader.
//
// Side Effects:
//
//	Writes the status line and possibly the problem body to the client.
//
// Complexity: O(1) time and memory.
// Thread Safety: not safe for concurrent use; one writer per request, as
// with any http.ResponseWriter.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	w.WriteHeader(http.StatusBadGateway) // client receives a 502 problem
//
// See Also: isProblem, writeProblem.
func (w *problemWriter) WriteHeader(code int) {
	if w.wroteHeader {
		return
	}
	w.wroteHeader = true
	if code >= http.StatusBadRequest && !isProblem(w.Header().Get("Content-Type")) {
		w.replaced = true
		writeProblem(w.ResponseWriter, w.req, code)
		return
	}
	w.ResponseWriter.WriteHeader(code)
}

// Write forwards body bytes, or discards them after a replacement.
//
// Description:
//
//	A Write before WriteHeader implies status 200, as with net/http. After
//	a replacement the upstream body is discarded while reporting success,
//	so that Traefik's proxy does not treat the client as gone.
//
// Business Justification:
//
//	See problemHandler.
//
// Parameters:
//   - b: body bytes from the upstream.
//
// Returns:
//   - int:   number of bytes accepted (len(b) when discarded).
//   - error: the error of the client connection, if any.
//
// Errors:
//   - any error returned by the underlying writer.
//
// Side Effects:
//
//	Writes to the client connection unless the response was replaced.
//
// Complexity: O(len(b)) time, O(1) memory.
// Thread Safety: not safe for concurrent use (one writer per request).
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	n, err := w.Write([]byte("{}"))
//
// See Also: problemWriter.WriteHeader.
func (w *problemWriter) Write(b []byte) (int, error) {
	if !w.wroteHeader {
		w.WriteHeader(http.StatusOK)
	}
	if w.replaced {
		return len(b), nil
	}
	return w.ResponseWriter.Write(b)
}

// Flush forwards a flush to the client when the underlying writer supports it.
//
// Description:
//
//	Keeps server-sent events (GET /api/v1/tasks/{taskId}/timer) streaming
//	through the middleware.
//
// Business Justification:
//
//	The waiting-time display depends on timely SSE delivery (CLAUDE.md 4.1).
//
// Parameters:
//
//	None.
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
//	Flushes buffered bytes to the client connection.
//
// Complexity: O(1) time and memory besides the flushed bytes.
// Thread Safety: not safe for concurrent use (one writer per request).
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	w.Flush()
//
// See Also: http.Flusher.
func (w *problemWriter) Flush() {
	if !w.wroteHeader {
		w.WriteHeader(http.StatusOK)
	}
	if f, ok := w.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// respondHandler is the handler of ModeNotFound and ModeHealth.
//
// Description:
//
//	Answers every request itself; the next handler is never called.
//
// Business Justification:
//
//	Gives the catch-all API router and the health router a response body
//	that Traefik cannot produce on its own.
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	h := &respondHandler{health: true}
//
// See Also: ModeNotFound, ModeHealth.
type respondHandler struct {
	// health selects the health document (true) or a 404 problem (false).
	health bool
}

// ServeHTTP writes the health document or a 404 problem.
//
// Description:
//
//	The health document is served for every method and path the router
//	sends here; HEAD requests receive the headers only, as net/http does.
//
// Business Justification:
//
//	See respondHandler.
//
// Parameters:
//   - rw:  the client response writer.
//   - req: the client request.
//
// Returns:
//
//	Nothing; the response is written to rw.
//
// Errors:
//
//	None.
//
// Side Effects:
//
//	Writes the response to the client connection.
//
// Complexity: O(len(path)) time and memory.
// Thread Safety: safe for concurrent use; the handler is stateless.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	h.ServeHTTP(rw, httptest.NewRequest("GET", "/health", nil))
//
// See Also: writeProblem, healthBody.
func (h *respondHandler) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	if !h.health {
		writeProblem(rw, req, http.StatusNotFound)
		return
	}
	rw.Header().Set("Content-Type", "application/json")
	rw.Header().Set("Cache-Control", "no-store")
	rw.WriteHeader(http.StatusOK)
	_, _ = rw.Write([]byte(healthBody))
}

// problem is an RFC 9457 problem details document.
//
// Description:
//
//	Uses the members type, title, status, detail and instance. Type is
//	always "about:blank", so title is the standard reason phrase of the
//	status (RFC 9457, section 4.2.1).
//
// Business Justification:
//
//	The error format of the AaaS public API (CLAUDE.md 4.1).
//
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	p := problem{Type: "about:blank", Title: "Not Found", Status: 404}
//
// See Also: writeProblem.
type problem struct {
	// Type identifies the problem type; always "about:blank".
	Type string `json:"type"`
	// Title is the reason phrase of Status.
	Title string `json:"title"`
	// Status repeats the HTTP status code.
	Status int `json:"status"`
	// Detail explains the occurrence; omitted when there is nothing to add.
	Detail string `json:"detail,omitempty"`
	// Instance is the request path that produced the problem.
	Instance string `json:"instance,omitempty"`
}

// writeProblem writes a problem document with the given status.
//
// Description:
//
//	Removes headers that describe a different body, sets the problem media
//	type and nosniff, writes the status and the JSON document. The body is
//	omitted for HEAD requests.
//
// Business Justification:
//
//	Single place where the gateway produces RFC 9457 documents.
//
// Parameters:
//   - rw:   the client response writer; its status must not be written yet.
//   - req:  the client request (path for `instance`, method for HEAD).
//   - code: HTTP status code, 400–599.
//
// Returns:
//
//	Nothing.
//
// Errors:
//
//	None; a failed client write is ignored (the client is gone).
//
// Side Effects:
//
//	Writes headers, status and body to the client connection.
//
// Complexity: O(len(path)) time and memory.
// Thread Safety: safe for concurrent use with distinct writers.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	writeProblem(rw, req, http.StatusServiceUnavailable)
//
// See Also: problem, detailFor.
func writeProblem(rw http.ResponseWriter, req *http.Request, code int) {
	header := rw.Header()
	for _, name := range []string{"Content-Length", "Content-Encoding", "Content-Range", "ETag"} {
		header.Del(name)
	}
	header.Set("Content-Type", problemContentType)
	header.Set("X-Content-Type-Options", "nosniff")
	header.Set("Cache-Control", "no-store")
	body, _ := json.Marshal(problem{
		Type:     "about:blank",
		Title:    http.StatusText(code),
		Status:   code,
		Detail:   detailFor(code),
		Instance: req.URL.Path,
	})
	rw.WriteHeader(code)
	if req.Method != http.MethodHead {
		_, _ = rw.Write(append(body, '\n'))
	}
}

// detailFor returns the human-readable explanation of a gateway error.
//
// Description:
//
//	Explains the statuses the gateway itself produces or most often
//	rewrites; other statuses get an empty detail, which is omitted.
//
// Business Justification:
//
//	A caller (the frontend, an operator) learns whether the request or an
//	upstream service is at fault without reading gateway logs.
//
// Parameters:
//   - code: HTTP status code, 400–599.
//
// Returns:
//   - string: the explanation, or "" when there is none.
//
// Errors:
//
//	None.
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
//	detailFor(502) // "The upstream service is unavailable."
//
// See Also: writeProblem.
func detailFor(code int) string {
	switch code {
	case http.StatusNotFound:
		return "No route of the AaaS API matches the request path."
	case http.StatusBadGateway:
		return "The upstream service is unavailable."
	case http.StatusServiceUnavailable:
		return "No healthy upstream server is available."
	case http.StatusGatewayTimeout:
		return "The upstream service did not respond in time."
	default:
		return ""
	}
}

// isProblem reports whether a Content-Type is application/problem+json.
//
// Description:
//
//	Parameters (`; charset=utf-8`) and letter case are ignored.
//
// Business Justification:
//
//	Upstream problem documents must pass through untouched.
//
// Parameters:
//   - contentType: value of the Content-Type header, possibly empty.
//
// Returns:
//   - bool: true for application/problem+json.
//
// Errors:
//
//	None.
//
// Side Effects:
//
//	None.
//
// Complexity: O(len(contentType)) time and memory.
// Thread Safety: safe for concurrent use.
// Owner: Platform Enablement Guild (PEG)
// Since: gateway v0.1.0
//
// Example:
//
//	isProblem("application/problem+json; charset=utf-8") // true
//
// See Also: problemContentType.
func isProblem(contentType string) bool {
	mediaType, _, _ := strings.Cut(contentType, ";")
	return strings.EqualFold(strings.TrimSpace(mediaType), problemContentType)
}
