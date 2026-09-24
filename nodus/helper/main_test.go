package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

func setup(t *testing.T, writeHook ...func(http.ResponseWriter, *http.Request)) (profile, *int) {
	t.Helper()
	directory = t.TempDir()
	if err := os.Chmod(directory, 0700); err != nil {
		t.Fatal(err)
	}
	bin := t.TempDir()
	script := `#!/bin/sh
case "$1" in
 lookup) file="$SECRET_TEST_DIR/$5"; [ -f "$file" ] && exec cat "$file"; exit 1 ;;
 store) file="$SECRET_TEST_DIR/$6"; cat > "$file" ;;
 clear) file="$SECRET_TEST_DIR/$5"; rm -f "$file" ;;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "secret-tool"), []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+":"+os.Getenv("PATH"))
	t.Setenv("SECRET_TEST_DIR", directory)
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v2/capabilities":
			fmt.Fprint(w, `{"contractVersion":"2.0","realmId":"realm_a","features":[]}`)
		case "/auth/pairings/redeem":
			var payload pendingPair
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil || payload.Code != "ABCDE-FGHIJ" || payload.DeviceID != "dev_a" || payload.RequestID != "req_a" {
				t.Errorf("changed pairing identity: %+v %v", payload, err)
			}
			fmt.Fprintf(w, `{"credential":%q,"tokenId":"token_a"}`, "token_a."+payload.Secret)
		case "/api/v2/changes":
			calls++
			if r.URL.Query().Get("after") == "0" {
				fmt.Fprint(w, `{"events":[{"revision":"1","resourceType":"note","resource":{"id":"note_1","kind":"text","title":"First","text":"Body","state":"live","revision":"1","updated":"2026-01-01T00:00:00Z"}}],"cursor":"1","until":"2","hasMore":true}`)
			} else {
				fmt.Fprint(w, `{"events":[{"revision":"2","resourceType":"note","resource":{"id":"note_2","kind":"text","title":"Second","text":"Next","state":"live","revision":"2","updated":"2026-01-02T00:00:00Z"}}],"cursor":"2","until":"2","hasMore":false}`)
			}
		case "/api/v2/notes/note_1":
			if r.Method == "GET" {
				fmt.Fprint(w, `{"id":"note_1","kind":"checklist","title":"Packing","state":"live","revision":"8","items":[{"id":"item_1","revision":"8","position":0,"text":"Egg","checked":true,"deleted":false}]}`)
			} else {
				t.Errorf("unexpected method: %s", r.Method)
				w.WriteHeader(405)
			}
		default:
			if strings.HasPrefix(r.URL.Path, "/api/v2/notes/note_") && (r.Method == "PUT" || (r.Method == "PATCH" && strings.HasSuffix(r.URL.Path, "/checked"))) {
				if len(writeHook) > 0 {
					writeHook[0](w, r)
					return
				}
				body, err := os.ReadFile(filepath.Join(directory, "mutation.json"))
				if err != nil {
					t.Error(err)
				}
				var record mutation
				if json.Unmarshal(body, &record) != nil || string(record.Body) == "" || record.State != "sending" {
					t.Error("write sent without durable exact journal")
				}
				fmt.Fprintf(w, `{"resourceType":"note","resourceId":%q,"revision":"3"}`, mutationNoteID(r.URL.Path))
			} else {
				t.Errorf("unexpected route: %s", r.URL.Path)
				w.WriteHeader(404)
			}
		}
	}))
	t.Cleanup(srv.Close)
	p := profile{Origin: srv.URL, TokenID: "token_a", DeviceID: "dev_a", Realm: "realm_a"}
	if err := save("profile.json", p); err != nil {
		t.Fatal(err)
	}
	if _, err := secret("store", "credential", p.Origin, "token_a.secret"); err != nil {
		t.Fatal(err)
	}
	return p, &calls
}
func TestFeedResumeAndCachedRead(t *testing.T) {
	p, calls := setup(t)
	syncNotes(0)
	c := loadCache(p)
	if c.Cursor != "1" || c.Until != "2" || len(c.Resources) != 1 {
		t.Fatalf("first page: %+v", c)
	}
	syncNotes(0)
	c = loadCache(p)
	if c.Cursor != "2" || c.Until != "" || len(c.Resources) != 2 || *calls != 2 {
		t.Fatalf("resume: %+v, %d calls", c, *calls)
	}
	detail("note_1", false)
	var selected note
	if err := read("detail.json", &selected); err != nil || selected.Text != "Body" {
		t.Fatalf("detail: %+v %v", selected, err)
	}
}
func TestPairReplaysProtectedPendingIdentity(t *testing.T) {
	p, _ := setup(t)
	if err := remove("profile.json"); err != nil {
		t.Fatal(err)
	}
	if _, err := secret("clear", "credential", p.Origin, ""); err != nil {
		t.Fatal(err)
	}
	pending := pendingPair{Code: "ABCDE-FGHIJ", DeviceID: "dev_a", RequestID: "req_a", Secret: strings.Repeat("a", 43)}
	raw, _ := json.Marshal(pending)
	if _, err := secret("store", "pending", p.Origin, string(raw)); err != nil {
		t.Fatal(err)
	}
	pair(p.Origin)
	if got := loadProfile(); got.TokenID != "token_a" || got.DeviceID != "dev_a" || got.Realm != "realm_a" {
		t.Fatalf("pairing profile: %+v", got)
	}
	if got := getCredential(p); got != "token_a."+pending.Secret {
		t.Fatal("wrong protected credential")
	}
	if got, _ := secret("lookup", "pending", p.Origin, ""); got != "" {
		t.Fatal("pending pairing was not cleared")
	}
}
func TestCreateJournalsAndCleansUp(t *testing.T) {
	setup(t)
	makeDraft()
	entries, err := filepath.Glob(filepath.Join(directory, "draft-*"))
	if err != nil || len(entries) != 1 {
		t.Fatalf("draft files: %v %v", entries, err)
	}
	if err := os.WriteFile(entries[0], []byte(`{"title":"Tea","text":"Remember milk"}`), 0600); err != nil {
		t.Fatal(err)
	}
	create(entries[0])
	if _, err := os.Stat(path("mutation.json")); !os.IsNotExist(err) {
		t.Fatalf("journal retained: %v", err)
	}
	if _, err := os.Stat(entries[0]); !os.IsNotExist(err) {
		t.Fatalf("draft retained: %v", err)
	}
}
func TestCreateChecklistUsesFreshItemIDs(t *testing.T) {
	var created struct {
		Kind  string `json:"kind"`
		Title string `json:"title"`
		Items []struct {
			ID   string `json:"id"`
			Text string `json:"text"`
		} `json:"items"`
	}
	setup(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PUT" {
			t.Errorf("unexpected method: %s", r.Method)
		}
		if err := json.NewDecoder(r.Body).Decode(&created); err != nil {
			t.Error(err)
		}
		fmt.Fprintf(w, `{"resourceType":"note","resourceId":%q,"revision":"3"}`, mutationNoteID(r.URL.Path))
	})
	makeDraft()
	files, _ := filepath.Glob(filepath.Join(directory, "draft-*"))
	if err := os.WriteFile(files[0], []byte(`{"kind":"checklist","title":"Packing","items":["Egg","","Milk"]}`), 0600); err != nil {
		t.Fatal(err)
	}
	create(files[0])
	if created.Kind != "checklist" || created.Title != "Packing" || len(created.Items) != 2 || created.Items[0].Text != "Egg" || created.Items[1].Text != "Milk" || !validID(created.Items[0].ID) || created.Items[0].ID == created.Items[1].ID {
		t.Fatalf("invalid checklist create: %+v", created)
	}
}
func TestCreateEmptyChecklistWithTitle(t *testing.T) {
	var input struct {
		Kind  string        `json:"kind"`
		Items []initialItem `json:"items"`
	}
	setup(t, func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
			t.Error(err)
		}
		fmt.Fprintf(w, `{"resourceType":"note","resourceId":%q,"revision":"3"}`, mutationNoteID(r.URL.Path))
	})
	makeDraft()
	files, _ := filepath.Glob(filepath.Join(directory, "draft-*"))
	if err := os.WriteFile(files[0], []byte(`{"kind":"checklist","title":"Empty for now"}`), 0600); err != nil {
		t.Fatal(err)
	}
	create(files[0])
	if input.Kind != "checklist" || input.Items == nil || len(input.Items) != 0 {
		t.Fatalf("empty checklist not encoded as array: %+v", input)
	}
}
func TestCheckedAssignmentUsesItemRevisionAndFreshDetail(t *testing.T) {
	var submitted struct {
		ExpectedRevision string `json:"expectedRevision"`
		Checked          bool   `json:"checked"`
		DeviceID         string `json:"deviceId"`
		RequestID        string `json:"requestId"`
	}
	p, _ := setup(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PATCH" || r.URL.Path != "/api/v2/notes/note_1/items/item_1/checked" {
			t.Errorf("wrong route: %s %s", r.Method, r.URL.Path)
		}
		var journaled mutation
		if err := read("mutation.json", &journaled); err != nil || journaled.State != "sending" || journaled.Method != "PATCH" {
			t.Errorf("no durable checked journal: %+v %v", journaled, err)
		}
		if err := json.NewDecoder(r.Body).Decode(&submitted); err != nil {
			t.Error(err)
		}
		fmt.Fprint(w, `{"resourceType":"note","resourceId":"note_1","revision":"8"}`)
	})
	c := cache{Realm: p.Realm, Cursor: "7", Resources: map[string]json.RawMessage{"note:note_1": json.RawMessage(`{"id":"note_1","kind":"checklist","title":"Packing","state":"live","revision":"6","items":[{"id":"item_1","revision":"7","position":0,"text":"Egg","checked":false,"deleted":false}]}`)}}
	if err := save("cache.json", c); err != nil {
		t.Fatal(err)
	}
	setChecked("note_1", "item_1", "7", "true")
	if submitted.ExpectedRevision != "7" || !submitted.Checked || submitted.DeviceID != p.DeviceID || !validID(submitted.RequestID) {
		t.Fatalf("wrong assignment: %+v", submitted)
	}
	detail("note_1", true)
	var n note
	if err := read("detail.json", &n); err != nil || !n.Items[0].Checked || n.Items[0].Revision != "8" {
		t.Fatalf("fresh detail: %+v %v", n, err)
	}
	var cached note
	if err := json.Unmarshal(loadCache(p).Resources["note:note_1"], &cached); err != nil || !cached.Items[0].Checked || cached.Items[0].Revision != "8" {
		t.Fatalf("fresh detail not retained: %+v %v", cached, err)
	}
}
func TestFreshDetailSurvivesOlderFeedPage(t *testing.T) {
	p, _ := setup(t)
	detail("note_1", true)
	syncNotes(0)
	c := loadCache(p)
	var kept note
	if err := json.Unmarshal(c.Resources["note:note_1"], &kept); err != nil || kept.Revision != "8" || len(kept.Items) != 1 || !kept.Items[0].Checked || c.Cursor != "1" {
		t.Fatalf("older feed overwrote fresh detail: %+v, cursor %s, %v", kept, c.Cursor, err)
	}
	syncNotes(0)
	c = loadCache(p)
	if err := json.Unmarshal(c.Resources["note:note_1"], &kept); err != nil || kept.Revision != "8" || c.Cursor != "2" {
		t.Fatalf("follow-up page regressed detail: %+v, cursor %s, %v", kept, c.Cursor, err)
	}
}
func TestCheckedConflictPreservesOriginalProposal(t *testing.T) {
	var writes atomic.Int32
	p, _ := setup(t, func(w http.ResponseWriter, r *http.Request) {
		writes.Add(1)
		if r.Method != "PATCH" {
			t.Errorf("wrong method: %s", r.Method)
		}
		w.WriteHeader(http.StatusConflict)
		fmt.Fprint(w, `{"error":"conflict","code":"durable_conflict","conflictId":"conflict_1","revision":"8"}`)
	})
	c := cache{Realm: p.Realm, Cursor: "7", Resources: map[string]json.RawMessage{"note:note_1": json.RawMessage(`{"id":"note_1","kind":"checklist","state":"live","revision":"6","items":[{"id":"item_1","revision":"7","position":0,"text":"Egg","checked":false,"deleted":false}]}`)}}
	if err := save("cache.json", c); err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "nodus-test-helper")
	if out, err := exec.Command("go", "build", "-o", binary, ".").CombinedOutput(); err != nil {
		t.Fatalf("build: %s %v", out, err)
	}
	cmd := exec.Command(binary, "--data-dir", directory, "checked", "note_1", "item_1", "6", "true")
	if out, err := cmd.CombinedOutput(); err == nil || !strings.Contains(string(out), "Item changed") {
		t.Fatalf("stale item not blocked: %s %v", out, err)
	}
	if writes.Load() != 0 {
		t.Fatalf("stale item sent %d writes", writes.Load())
	}
	cmd = exec.Command(binary, "--data-dir", directory, "checked", "note_1", "item_1", "7", "true")
	if out, err := cmd.CombinedOutput(); err == nil || !strings.Contains(string(out), "conflicted") {
		t.Fatalf("conflict not surfaced: %s %v", out, err)
	}
	m, ok := journal()
	if writes.Load() != 1 || !ok || m.State != "conflict" || m.Method != "PATCH" || !strings.Contains(string(m.Body), `"expectedRevision":"7"`) {
		t.Fatalf("conflict proposal lost: %+v, %d writes", m, writes.Load())
	}
}
func TestLostCheckedWriteRetriesIdenticalRequest(t *testing.T) {
	var sent [][]byte
	p, _ := setup(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PATCH" || r.URL.Path != "/api/v2/notes/note_1/items/item_1/checked" {
			t.Errorf("wrong checked route: %s %s", r.Method, r.URL.Path)
		}
		body, _ := io.ReadAll(r.Body)
		sent = append(sent, body)
		if len(sent) == 1 {
			conn, _, err := w.(http.Hijacker).Hijack()
			if err != nil {
				t.Error(err)
			} else {
				conn.Close()
			}
			return
		}
		fmt.Fprint(w, `{"resourceType":"note","resourceId":"note_1","revision":"8"}`)
	})
	c := cache{Realm: p.Realm, Cursor: "7", Resources: map[string]json.RawMessage{"note:note_1": json.RawMessage(`{"id":"note_1","kind":"checklist","state":"live","revision":"6","items":[{"id":"item_1","revision":"7","position":0,"text":"Egg","checked":false,"deleted":false}]}`)}}
	if err := save("cache.json", c); err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "nodus-test-helper")
	if out, err := exec.Command("go", "build", "-o", binary, ".").CombinedOutput(); err != nil {
		t.Fatalf("build: %s %v", out, err)
	}
	cmd := exec.Command(binary, "--data-dir", directory, "checked", "note_1", "item_1", "7", "true")
	if out, err := cmd.CombinedOutput(); err == nil || !strings.Contains(string(out), "outcome unknown") {
		t.Fatalf("lost checked response: %s %v", out, err)
	}
	m, ok := journal()
	if !ok || m.State != "unknown" || m.Method != "PATCH" || m.TokenID != p.TokenID {
		t.Fatalf("unknown checked evidence: %+v", m)
	}
	cmd = exec.Command(binary, "--data-dir", directory, "retry")
	if out, err := cmd.CombinedOutput(); err != nil || !strings.Contains(string(out), `"noteId":"note_1"`) {
		t.Fatalf("checked retry: %s %v", out, err)
	}
	if len(sent) != 2 || string(sent[0]) != string(sent[1]) {
		t.Fatal("checked retry changed request body")
	}
	if _, ok := journal(); ok {
		t.Fatal("confirmed checked journal not cleared")
	}
}
func TestNoteSummaryPrefersOpenItem(t *testing.T) {
	c := cache{Resources: map[string]json.RawMessage{"note:n": json.RawMessage(`{"id":"n","kind":"checklist","state":"live","updated":"2026-01-01T00:00:00Z","items":[{"id":"i1","position":0,"text":"Done","checked":true},{"id":"i2","position":1,"text":"Open","checked":false}]}`)}}
	notes, _, _ := noteSummaries(c, 0)
	if len(notes) != 1 || notes[0].Preview != "Open" || notes[0].Checked != 1 || notes[0].Items != 2 {
		t.Fatalf("summary: %+v", notes)
	}
}
func TestLostWriteRetriesIdenticalRequest(t *testing.T) {
	var sent [][]byte
	p, _ := setup(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		sent = append(sent, body)
		if len(sent) == 1 {
			conn, _, err := w.(http.Hijacker).Hijack()
			if err != nil {
				t.Error(err)
			} else {
				conn.Close()
			}
			return
		}
		fmt.Fprintf(w, `{"resourceType":"note","resourceId":%q,"revision":"3"}`, strings.TrimPrefix(r.URL.Path, "/api/v2/notes/"))
	})
	makeDraft()
	files, _ := filepath.Glob(filepath.Join(directory, "draft-*"))
	if len(files) != 1 {
		t.Fatal("draft missing")
	}
	if err := os.WriteFile(files[0], []byte(`{"title":"Lost","text":"Still one note"}`), 0600); err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(t.TempDir(), "nodus-test-helper")
	if out, err := exec.Command("go", "build", "-o", binary, ".").CombinedOutput(); err != nil {
		t.Fatalf("build: %s %v", out, err)
	}
	cmd := exec.Command(binary, "--data-dir", directory, "create", files[0])
	if out, err := cmd.CombinedOutput(); err == nil || !strings.Contains(string(out), "outcome unknown") {
		t.Fatalf("lost response: %s %v", out, err)
	}
	m, ok := journal()
	if !ok || m.State != "unknown" || m.Realm != p.Realm {
		t.Fatalf("unknown evidence: %+v", m)
	}
	cmd = exec.Command(binary, "--data-dir", directory, "retry")
	if out, err := cmd.CombinedOutput(); err != nil || !strings.Contains(string(out), `"state":"saved"`) {
		t.Fatalf("exact retry: %s %v", out, err)
	}
	if len(sent) != 2 || string(sent[0]) != string(sent[1]) {
		t.Fatal("retry changed request body")
	}
	if _, ok := journal(); ok {
		t.Fatal("confirmed journal not cleared")
	}
}
func TestSendingBecomesUnknownWithoutReencoding(t *testing.T) {
	setup(t)
	body := json.RawMessage(`{"deviceId":"dev_a","requestId":"req_a", "kind":"text","title":"a","text":"b"}`)
	m := mutation{State: "sending", Realm: "realm_a", TokenID: "token_a", DeviceID: "dev_a", RequestID: "req_a", Method: "PUT", Path: "/api/v2/notes/note_created", Body: body}
	if err := save("mutation.json", m); err != nil {
		t.Fatal(err)
	}
	got, ok := journal()
	if !ok || got.State != "unknown" || string(got.Body) != string(body) {
		t.Fatalf("journal: %+v", got)
	}
}
func TestPageAndRevisionBounds(t *testing.T) {
	for _, bad := range []string{"01", "1.0", "9223372036854775808", "", "-1"} {
		if validDecimal(bad) {
			t.Errorf("accepted %q", bad)
		}
	}
	if compareDecimal("9", "10") >= 0 || !validDecimal("9223372036854775807") {
		t.Fatal("decimal comparison")
	}
	c := cache{Resources: map[string]json.RawMessage{}}
	for i := 0; i < 43; i++ {
		c.Resources[fmt.Sprintf("note:%d", i)] = json.RawMessage(fmt.Sprintf(`{"id":"note_%d","state":"live","title":"%d","updated":"%04d"}`, i, i, i))
	}
	first, next, totals := noteSummaries(c, 0)
	second, end, _ := noteSummaries(c, 40)
	if len(first) != 40 || !next || len(second) != 3 || end || first[0].ID == second[0].ID || totals.Active != 43 {
		t.Fatal("page boundary")
	}
	if !strings.HasPrefix(first[0].ID, "note_") {
		t.Fatal("wrong note")
	}
}
