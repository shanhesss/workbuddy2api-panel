package panel

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/misakano7545/workbuddy2api-panel/internal/auth"
	"github.com/misakano7545/workbuddy2api-panel/internal/pool"
	"github.com/misakano7545/workbuddy2api-panel/internal/proxypool"
)

func TestProxyAPIAuthenticationBindingAndRemoval(t *testing.T) {
	manager, err := proxypool.New(filepath.Join(t.TempDir(), "proxy-pool.json"), nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer manager.Close()
	accounts := pool.New("")
	accounts.Add(&auth.Auth{UID: "u1", AccessToken: "token"})
	p := New(Config{Pool: accounts, ProxyPool: manager, APIKey: "panel-key"})
	call := func(method, path, body, key string) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(method, "/panel/api/"+path, strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+key)
		rec := httptest.NewRecorder()
		p.ServeHTTP(rec, req)
		return rec
	}
	for _, route := range []struct{ method, path string }{
		{"GET", "proxies"}, {"POST", "proxies"}, {"PATCH", "proxies/missing"},
		{"DELETE", "proxies/missing"}, {"POST", "proxies/check"}, {"POST", "proxies/missing/check"},
		{"PUT", "proxies/health"}, {"PUT", "accounts/u1/proxy"},
	} {
		if got := call(route.method, route.path, "{}", "wrong"); got.Code != http.StatusUnauthorized {
			t.Fatalf("unauthorized %s %s: %d", route.method, route.path, got.Code)
		}
	}
	imported := call("POST", "proxies", `{"lines":"http://user:TOPSECRET@localhost:8080\nbad://host\nhttp://user:TOPSECRET@localhost:8080"}`, "panel-key")
	if imported.Code != 200 || strings.Contains(imported.Body.String(), "TOPSECRET") {
		t.Fatalf("import: %d %s", imported.Code, imported.Body.String())
	}
	var data struct {
		Results []proxypool.ImportResult `json:"results"`
	}
	if err := json.Unmarshal(imported.Body.Bytes(), &data); err != nil || len(data.Results) != 3 {
		t.Fatalf("results=%+v err=%v", data, err)
	}
	id := data.Results[0].ID
	for _, route := range []struct {
		method, path, body string
		want               int
	}{
		{"GET", "proxies", "", 200},
		{"PATCH", "proxies/" + id, `{"name":"Office","password":""}`, 200},
		{"PUT", "accounts/u1/proxy", `{"mode":"fixed","proxy_id":"` + id + `"}`, 200},
		{"DELETE", "proxies/" + id, "", 409},
		{"POST", "proxies/" + id + "/check", "", 202},
		{"POST", "proxies/check", "", 202},
		{"POST", "proxies/missing/check", "", 404},
		{"POST", "proxies", `{"lines":"http://localhost:1234"} {}`, 400},
		{"PUT", "accounts/missing/proxy", `{"mode":"direct"}`, 404},
		{"PUT", "accounts/u1/proxy", `{"mode":"fixed","proxy_id":"missing"}`, 404},
		{"PUT", "accounts/u1/proxy", `{"mode":"bogus"}`, 400},
		{"PUT", "proxies/health", `{"url":"file:///tmp/check","interval_seconds":60}`, 400},
		{"POST", "accounts/u1/remove", "", 200},
		{"DELETE", "proxies/" + id, "", 200},
	} {
		got := call(route.method, route.path, route.body, "panel-key")
		if got.Code != route.want || strings.Contains(got.Body.String(), "TOPSECRET") {
			t.Fatalf("%s %s: %d %s; want %d", route.method, route.path, got.Code, got.Body.String(), route.want)
		}
	}
	if len(manager.Snapshot().Bindings) != 0 {
		t.Fatal("account removal retained binding")
	}
}

func TestProxyAPIRejectsOversizedBody(t *testing.T) {
	m, err := proxypool.New("", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer m.Close()
	p := New(Config{Pool: pool.New(""), ProxyPool: m})
	body := `{"lines":"` + strings.Repeat("x", 1<<20) + `"}`
	rec := httptest.NewRecorder()
	p.ServeHTTP(rec, httptest.NewRequest("POST", "/panel/api/proxies", strings.NewReader(body)))
	if rec.Code != http.StatusBadRequest || len(m.Snapshot().Proxies) != 0 {
		t.Fatalf("oversized request: %d", rec.Code)
	}
}
