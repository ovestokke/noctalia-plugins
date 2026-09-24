// nodus-noctalia is the Linux Secret Service-backed transport for the Noctalia plugin.
// No credential, pairing secret or note text is ever accepted as a command argument.
package main

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

type profile struct {
	Origin   string `json:"origin"`
	TokenID  string `json:"tokenId"`
	DeviceID string `json:"deviceId"`
	Realm    string `json:"realmId"`
}
type pendingPair struct {
	Code      string `json:"code"`
	DeviceID  string `json:"deviceId"`
	RequestID string `json:"requestId"`
	Secret    string `json:"credentialSecret"`
}
type cache struct {
	Realm     string                     `json:"realmId"`
	Cursor    string                     `json:"cursor"`
	Until     string                     `json:"until"`
	Resources map[string]json.RawMessage `json:"resources"`
}
type mutation struct {
	State     string `json:"state"`
	Realm     string `json:"realmId"`
	TokenID   string `json:"tokenId"`
	DeviceID  string `json:"deviceId"`
	RequestID string `json:"requestId"`
	Method    string `json:"method"`
	Path      string `json:"path"`
	Body      []byte `json:"body"`
	Draft     string `json:"draft"`
}
type initialItem struct {
	ID   string `json:"id"`
	Text string `json:"text"`
}
type checklistItem struct {
	ID       string `json:"id"`
	Text     string `json:"text"`
	Checked  bool   `json:"checked"`
	Position int    `json:"position"`
	Revision string `json:"revision"`
	Deleted  bool   `json:"deleted"`
}
type note struct {
	ID       string          `json:"id"`
	Kind     string          `json:"kind"`
	Title    string          `json:"title"`
	Text     string          `json:"text"`
	State    string          `json:"state"`
	Revision string          `json:"revision"`
	Archived bool            `json:"archived"`
	Updated  string          `json:"updated"`
	Items    []checklistItem `json:"items"`
}
type envelope struct {
	OK      bool      `json:"ok"`
	State   string    `json:"state,omitempty"`
	Message string    `json:"message,omitempty"`
	Path    string    `json:"path,omitempty"`
	Notes   []summary `json:"notes,omitempty"`
	Counts  *counts   `json:"counts,omitempty"`
	More    bool      `json:"more,omitempty"`
	Next    bool      `json:"next,omitempty"`
	Note    *note     `json:"note,omitempty"`
	NoteID  string    `json:"noteId,omitempty"`
	Origin  string    `json:"origin,omitempty"`
}
type counts struct {
	Active  int `json:"active"`
	Archive int `json:"archive"`
	Trash   int `json:"trash"`
}
type summary struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Preview  string `json:"preview"`
	Kind     string `json:"kind"`
	State    string `json:"state"`
	Archived bool   `json:"archived"`
	Updated  string `json:"updated"`
	Checked  int    `json:"checked"`
	Items    int    `json:"items"`
}
type apiError struct {
	Error string `json:"error"`
	Code  string `json:"code"`
}

var directory string

func main() {
	flag.StringVar(&directory, "data-dir", "", "private state directory (default: XDG_STATE_HOME/nodus-noctalia)")
	flag.Parse()
	if directory == "" {
		root := os.Getenv("XDG_STATE_HOME")
		if !filepath.IsAbs(root) {
			home, err := os.UserHomeDir()
			if err != nil {
				die("Home directory unavailable")
			}
			root = filepath.Join(home, ".local/state")
		}
		directory = filepath.Join(root, "nodus-noctalia")
	}
	if !filepath.IsAbs(directory) {
		die("State directory must be absolute")
	}
	if err := os.MkdirAll(directory, 0700); err != nil {
		die("Cannot create private state directory")
	}
	st, err := os.Lstat(directory)
	if err != nil || !st.IsDir() || st.Mode().Perm() != 0700 {
		die("State directory must be a private 0700 directory")
	}
	lock, err := os.OpenFile(filepath.Join(directory, "lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		die("Cannot lock state")
	}
	defer lock.Close()
	if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		die("Cannot lock state")
	}
	switch flag.Arg(0) {
	case "pair":
		pair(flag.Arg(1))
	case "sync":
		offset, err := strconv.Atoi(flag.Arg(1))
		if err != nil || offset < 0 || offset > 1000000 {
			die("Invalid note page")
		}
		syncNotes(offset)
	case "detail":
		detail(flag.Arg(1), flag.Arg(2) == "fresh")
	case "draft":
		makeDraft()
	case "create":
		create(flag.Arg(1))
	case "checked":
		setChecked(flag.Arg(1), flag.Arg(2), flag.Arg(3), flag.Arg(4))
	case "retry":
		retry()
	case "status":
		status()
	default:
		die("Use pair ORIGIN, sync OFFSET, detail ID, draft, create PATH, checked NOTE ITEM REVISION true|false, retry or status")
	}
}
func result(v envelope) {
	b, err := json.Marshal(v)
	if err != nil {
		die("Cannot encode response")
	}
	fmt.Println(string(b))
}
func die(message string) { result(envelope{OK: false, State: "error", Message: message}); os.Exit(1) }
func id(prefix string) string {
	b := make([]byte, 18)
	if _, err := rand.Read(b); err != nil {
		die("Random source unavailable")
	}
	return prefix + base64.RawURLEncoding.EncodeToString(b)
}
func validID(s string) bool {
	if len(s) < 1 || len(s) > 128 {
		return false
	}
	for _, c := range s {
		if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-') {
			return false
		}
	}
	return true
}
func compareDecimal(a, b string) int {
	if len(a) < len(b) {
		return -1
	}
	if len(a) > len(b) {
		return 1
	}
	return strings.Compare(a, b)
}
func validDecimal(s string) bool {
	if s == "0" {
		return true
	}
	if s == "" || s[0] < '1' || s[0] > '9' || len(s) > 19 {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return len(s) < 19 || s <= "9223372036854775807"
}
func origin(raw string) string {
	u, err := url.Parse(raw)
	if err != nil || u.User != nil || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" || (u.Path != "" && u.Path != "/") || u.Opaque != "" || u.Host == "" {
		die("Enter an HTTPS origin without a path, query or credentials")
	}
	if u.Scheme != "https" && !(u.Scheme == "http" && (u.Hostname() == "localhost" || u.Hostname() == "127.0.0.1" || u.Hostname() == "::1")) {
		die("HTTPS is required outside loopback")
	}
	u.Path = ""
	return u.String()
}
func path(name string) string { return filepath.Join(directory, name) }
func read(name string, dst any) error {
	b, err := os.ReadFile(path(name))
	if err != nil {
		return err
	}
	return json.Unmarshal(b, dst)
}

// Atomic replacement includes both the file and its directory in the durability boundary.
func save(name string, value any) error {
	b, err := json.Marshal(value)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(directory, ".write-")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if err = f.Chmod(0600); err == nil {
		_, err = f.Write(b)
	}
	if err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if err = os.Rename(f.Name(), path(name)); err != nil {
		return err
	}
	return flushDir()
}
func flushDir() error {
	d, err := os.Open(directory)
	if err != nil {
		return err
	}
	defer d.Close()
	return d.Sync()
}
func remove(name string) error {
	if err := os.Remove(path(name)); err != nil && !os.IsNotExist(err) {
		return err
	}
	return flushDir()
}
func loadProfile() profile {
	var p profile
	if read("profile.json", &p) != nil || p.Origin == "" || !validID(p.TokenID) || !validID(p.DeviceID) || !validID(p.Realm) {
		die("Pair this device in a terminal first")
	}
	return p
}
func loadCache(p profile) cache {
	var c cache
	err := read("cache.json", &c)
	if os.IsNotExist(err) {
		return cache{Realm: p.Realm, Cursor: "0", Resources: map[string]json.RawMessage{}}
	}
	if err != nil || c.Realm != p.Realm || !validDecimal(c.Cursor) || c.Resources == nil || (c.Until != "" && !validDecimal(c.Until)) {
		die("Local feed state needs manual recovery; no data was discarded")
	}
	return c
}
func secret(action, kind, origin string, input string) (string, error) {
	args := []string{action}
	if action == "store" {
		args = append(args, "--label=Nodus Noctalia "+kind)
	}
	args = append(args, "application", "nodus-noctalia", "kind", kind, "origin", origin)
	cmd := exec.Command("secret-tool", args...)
	if action == "store" {
		cmd.Stdin = strings.NewReader(input)
	}
	out, err := cmd.Output()
	if err != nil {
		if action == "lookup" {
			return "", nil // secret-tool exits nonzero when no matching entry exists.
		}
		return "", errors.New("Secret Service is locked or unavailable")
	}
	return strings.TrimSuffix(string(out), "\n"), nil
}
func getCredential(p profile) string {
	s, err := secret("lookup", "credential", p.Origin, "")
	if err != nil || !strings.HasPrefix(s, p.TokenID+".") {
		die("Credential unavailable; unlock Secret Service or pair this device")
	}
	return s
}
func terminalCode() string {
	f, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		die("Pair in a terminal with a controlling TTY")
	}
	defer f.Close()
	var old syscall.Termios
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&old))); errno != 0 {
		die("Cannot protect pairing code input")
	}
	term := old
	term.Lflag &^= syscall.ECHO
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), uintptr(syscall.TCSETS), uintptr(unsafe.Pointer(&term))); errno != 0 {
		die("Cannot disable terminal echo")
	}
	defer syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), uintptr(syscall.TCSETS), uintptr(unsafe.Pointer(&old)))
	fmt.Fprint(f, "Pairing code: ")
	raw := make([]byte, 0, 32)
	one := make([]byte, 1)
	for len(raw) < 32 {
		n, e := f.Read(one)
		if e != nil || n == 0 || one[0] == '\n' || one[0] == '\r' {
			break
		}
		raw = append(raw, one[0])
	}
	fmt.Fprintln(f)
	return strings.TrimSpace(string(raw))
}

var transport = &http.Client{Timeout: 20 * time.Second, Transport: &http.Transport{Proxy: nil}, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}

func request(p profile, credential, method, route string, body []byte) (int, []byte, error) {
	req, err := http.NewRequest(method, p.Origin+route, bytes.NewReader(body))
	if err != nil {
		return 0, nil, err
	}
	if credential != "" {
		req.Header.Set("Authorization", "Bearer "+credential)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	r, err := transport.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer r.Body.Close()
	data, err := io.ReadAll(io.LimitReader(r.Body, 16*1024*1024+1))
	if err != nil {
		return 0, nil, err
	}
	if len(data) > 16*1024*1024 {
		return 0, nil, errors.New("Response exceeds safety limit")
	}
	if bytes.Contains(data, []byte(credential)) && credential != "" {
		return 0, nil, errors.New("Server echoed protected credential")
	}
	return r.StatusCode, data, nil
}
func discover(p profile, credential string) (string, error) {
	code, b, err := request(p, credential, "GET", "/api/v2/capabilities", nil)
	if err != nil {
		return "", err
	}
	if code != 200 {
		return "", fmt.Errorf("capabilities HTTP %d", code)
	}
	var v struct {
		ContractVersion string   `json:"contractVersion"`
		RealmID         string   `json:"realmId"`
		Features        []string `json:"features"`
	}
	if json.Unmarshal(b, &v) != nil || v.ContractVersion != "2.0" || !validID(v.RealmID) {
		return "", errors.New("unsupported Nodus contract")
	}
	return v.RealmID, nil
}
func capabilities(p profile, credential string) string {
	realm, err := discover(p, credential)
	if err != nil {
		die("Cannot authenticate Nodus capabilities: " + err.Error())
	}
	return realm
}
func pair(raw string) {
	target := origin(raw)
	var existing profile
	if read("profile.json", &existing) == nil {
		die("Already paired; credential replacement requires explicit recovery")
	}
	// Pending identity is kept in Secret Service before the first network request.
	rawPending, err := secret("lookup", "pending", target, "")
	if err != nil {
		die(err.Error())
	}
	var pair pendingPair
	if rawPending != "" {
		if json.Unmarshal([]byte(rawPending), &pair) != nil || pair.Code == "" {
			die("Protected pending pairing needs manual recovery")
		}
		fmt.Fprintln(os.Stderr, "Retrying the original pairing redemption")
	} else {
		code := terminalCode()
		if code == "" {
			die("Pairing code is empty")
		}
		b := make([]byte, 32)
		if _, err = rand.Read(b); err != nil {
			die("Random source unavailable")
		}
		pair = pendingPair{Code: code, DeviceID: id("dev_"), RequestID: id("req_"), Secret: base64.RawURLEncoding.EncodeToString(b)}
		enc, _ := json.Marshal(pair)
		if _, err = secret("store", "pending", target, string(enc)); err != nil {
			die(err.Error())
		}
	}
	body, _ := json.Marshal(pair)
	p := profile{Origin: target}
	status, b, err := request(p, "", "POST", "/auth/pairings/redeem", body)
	if err != nil {
		die("Pairing outcome unknown; run pair with the same origin to retry exactly")
	}
	if status != 200 {
		die("Pairing was rejected or temporarily unavailable (HTTP " + fmt.Sprint(status) + "); pending evidence retained")
	}
	var redeemed struct {
		Credential string `json:"credential"`
		TokenID    string `json:"tokenId"`
	}
	if json.Unmarshal(b, &redeemed) != nil || !validID(redeemed.TokenID) || redeemed.Credential != redeemed.TokenID+"."+pair.Secret {
		die("Unexpected pairing receipt; pending evidence retained")
	}
	if _, err = secret("store", "credential", target, redeemed.Credential); err != nil {
		die(err.Error())
	}
	p.TokenID = redeemed.TokenID
	p.DeviceID = pair.DeviceID
	p.Realm = capabilities(p, redeemed.Credential)
	if err = save("profile.json", p); err != nil {
		die("Could not persist pairing profile; pending evidence retained")
	}
	if _, err = secret("clear", "pending", target, ""); err != nil {
		die("Paired; could not clear protected pending evidence")
	}
	result(envelope{OK: true, State: "paired", Origin: target})
}
func validMutationPath(method, route string) bool {
	const prefix = "/api/v2/notes/"
	if !strings.HasPrefix(route, prefix) {
		return false
	}
	parts := strings.Split(strings.TrimPrefix(route, prefix), "/")
	if method == "PUT" {
		return len(parts) == 1 && validID(parts[0])
	}
	return method == "PATCH" && len(parts) == 4 && validID(parts[0]) && parts[1] == "items" && validID(parts[2]) && parts[3] == "checked"
}
func mutationNoteID(route string) string {
	return strings.SplitN(strings.TrimPrefix(route, "/api/v2/notes/"), "/", 2)[0]
}
func journal() (mutation, bool) {
	var m mutation
	err := read("mutation.json", &m)
	if os.IsNotExist(err) {
		return m, false
	}
	if err != nil || !validID(m.RequestID) || len(m.Body) == 0 || !validMutationPath(m.Method, m.Path) {
		die("Mutation journal needs manual recovery")
	}
	if m.State == "sending" {
		m.State = "unknown" // Process death after dispatch cannot prove non-commit.
		if save("mutation.json", m) != nil {
			die("Cannot preserve unknown write")
		}
	}
	return m, true
}
func noteSummaries(c cache, offset int) ([]summary, bool, counts) {
	notes := []note{}
	counts := counts{}
	for key, raw := range c.Resources {
		if !strings.HasPrefix(key, "note:") {
			continue
		}
		var n note
		if json.Unmarshal(raw, &n) == nil && n.State != "purged" {
			notes = append(notes, n)
			if n.State == "trash" {
				counts.Trash++
			} else if n.Archived {
				counts.Archive++
			} else {
				counts.Active++
			}
		}
	}
	sort.Slice(notes, func(i, j int) bool { return notes[i].Updated > notes[j].Updated })
	if offset > len(notes) {
		offset = len(notes)
	}
	notes = notes[offset:]
	next := len(notes) > 40
	if next {
		notes = notes[:40]
	}
	out := make([]summary, 0, len(notes))
	for _, n := range notes {
		preview := n.Text
		if n.Kind == "checklist" {
			preview = ""
			var firstOpen, firstCompleted *checklistItem
			for index := range n.Items {
				item := &n.Items[index]
				if item.Deleted {
					continue
				}
				if item.Checked {
					if firstCompleted == nil || item.Position < firstCompleted.Position {
						firstCompleted = item
					}
				} else if firstOpen == nil || item.Position < firstOpen.Position {
					firstOpen = item
				}
			}
			if firstOpen != nil {
				preview = firstOpen.Text
			} else if firstCompleted != nil {
				preview = firstCompleted.Text
			}
		}
		r := []rune(strings.ReplaceAll(preview, "\n", " "))
		if len(r) > 110 {
			preview = string(r[:110]) + "…"
		} else {
			preview = string(r)
		}
		itemCount, checked := 0, 0
		for _, item := range n.Items {
			if !item.Deleted {
				itemCount++
				if item.Checked {
					checked++
				}
			}
		}
		out = append(out, summary{ID: n.ID, Title: n.Title, Preview: preview, Kind: n.Kind, State: n.State, Archived: n.Archived, Updated: n.Updated, Checked: checked, Items: itemCount})
	}
	return out, next, counts
}
func syncNotes(offset int) {
	p := loadProfile()
	cred := getCredential(p)
	c := loadCache(p)
	state := "connected"
	realm, discoveryError := discover(p, cred)
	if discoveryError == nil && realm != p.Realm {
		die("Realm changed; old notes and writes preserved. Pair a new isolated client before reconciliation")
	}
	if discoveryError != nil {
		state = "offline"
		if strings.Contains(discoveryError.Error(), "HTTP 401") || strings.Contains(discoveryError.Error(), "HTTP 403") {
			state = "auth"
		}
		if strings.Contains(discoveryError.Error(), "HTTP 429") {
			state = "rate_limited"
		}
	}
	more := false
	after := c.Cursor
	route := "/api/v2/changes?after=" + after + "&limit=10"
	if c.Until != "" {
		route += "&until=" + c.Until
	}
	status, b, err := 0, []byte(nil), discoveryError
	if err == nil {
		status, b, err = request(p, cred, "GET", route, nil)
	}
	if err != nil || status != 200 {
		if state == "connected" {
			state = "offline"
		}
		if status == 429 {
			state = "rate_limited"
		}
		if status == 401 || status == 403 {
			state = "auth"
		}
	} else {
		var page struct {
			Events []struct {
				Revision     string          `json:"revision"`
				ResourceType string          `json:"resourceType"`
				Resource     json.RawMessage `json:"resource"`
			} `json:"events"`
			Cursor  string `json:"cursor"`
			Until   string `json:"until"`
			HasMore bool   `json:"hasMore"`
		}
		if json.Unmarshal(b, &page) != nil || !validDecimal(page.Cursor) || !validDecimal(page.Until) || compareDecimal(page.Cursor, c.Cursor) < 0 || compareDecimal(page.Cursor, page.Until) > 0 || (page.HasMore && page.Cursor == c.Cursor) || (c.Until != "" && page.Until != c.Until) || (!page.HasMore && page.Cursor != page.Until) {
			die("Invalid change page; cursor was not advanced")
		}
		previous := c.Cursor
		for _, event := range page.Events {
			if !validDecimal(event.Revision) || compareDecimal(event.Revision, previous) <= 0 || compareDecimal(event.Revision, page.Until) > 0 || !json.Valid(event.Resource) {
				die("Invalid feed event; cursor was not advanced")
			}
			var resource struct {
				ID       string `json:"id"`
				Revision string `json:"revision"`
			}
			if json.Unmarshal(event.Resource, &resource) != nil || !validID(resource.ID) || resource.Revision != event.Revision {
				die("Invalid feed snapshot; cursor was not advanced")
			}
			if event.ResourceType != "note" && event.ResourceType != "tag" && event.ResourceType != "notebook" {
				die("Unknown feed resource; cursor was not advanced")
			}
			key := event.ResourceType + ":" + resource.ID
			if retained, ok := c.Resources[key]; ok {
				var existing struct {
					Revision string `json:"revision"`
				}
				if json.Unmarshal(retained, &existing) != nil || !validDecimal(existing.Revision) {
					die("Retained snapshot is invalid; cursor was not advanced")
				}
				if compareDecimal(existing.Revision, event.Revision) >= 0 {
					previous = event.Revision
					continue // A fresh detail read may be ahead of the committed feed cursor.
				}
			}
			c.Resources[key] = event.Resource
			previous = event.Revision
		}
		if len(page.Events) > 0 && compareDecimal(page.Cursor, previous) < 0 {
			die("Invalid change cursor; cursor was not advanced")
		}
		c.Cursor = page.Cursor
		if page.HasMore {
			c.Until = page.Until
		} else {
			c.Until = ""
		}
		if err = save("cache.json", c); err != nil {
			die("Could not commit change page")
		}
		more = page.HasMore
	}
	if m, ok := journal(); ok {
		state = m.State
	}
	notes, next, totals := noteSummaries(c, offset)
	result(envelope{OK: true, State: state, Notes: notes, Counts: &totals, More: more, Next: next, Origin: p.Origin})
}
func detail(noteID string, fresh bool) {
	if !validID(noteID) {
		die("Invalid note ID")
	}
	p := loadProfile()
	var raw []byte
	if fresh {
		cred := getCredential(p)
		if capabilities(p, cred) != p.Realm {
			die("Realm changed; old note preserved")
		}
		code, body, err := request(p, cred, "GET", "/api/v2/notes/"+noteID, nil)
		if err != nil || code != 200 {
			die("Note saved, but a fresh read failed; reopen it to refresh")
		}
		raw = body
	} else {
		c := loadCache(p)
		cached, ok := c.Resources["note:"+noteID]
		if !ok {
			die("Note is not cached yet")
		}
		raw = cached
	}
	var n note
	if json.Unmarshal(raw, &n) != nil || n.ID != noteID || (fresh && !validDecimal(n.Revision)) {
		die("Note snapshot is invalid")
	}
	if fresh {
		c := loadCache(p)
		if previous, ok := c.Resources["note:"+noteID]; ok {
			var old note
			if json.Unmarshal(previous, &old) != nil || !validDecimal(old.Revision) || compareDecimal(n.Revision, old.Revision) < 0 {
				die("Fresh note revision is older than the retained snapshot")
			}
		}
		c.Resources["note:"+noteID] = raw
		if err := save("cache.json", c); err != nil {
			die("Could not retain fresh note snapshot")
		}
	}
	if err := save("detail.json", n); err != nil {
		die("Could not open cached note")
	}
	result(envelope{OK: true, Path: path("detail.json")})
}
func makeDraft() {
	loadProfile()
	if _, ok := journal(); ok {
		die("Review the pending mutation before creating another note")
	}
	f, err := os.CreateTemp(directory, "draft-")
	if err != nil {
		die("Cannot create private draft")
	}
	name := f.Name()
	if err = f.Chmod(0600); err == nil {
		err = f.Sync()
	}
	f.Close()
	if err != nil || flushDir() != nil {
		die("Cannot secure private draft")
	}
	result(envelope{OK: true, Path: name})
}
func create(draftPath string) {
	p := loadProfile()
	if _, ok := journal(); ok {
		die("Resolve the previous write before creating another note")
	}
	if filepath.Dir(draftPath) != directory || !strings.HasPrefix(filepath.Base(draftPath), "draft-") {
		die("Invalid private draft path")
	}
	f, err := os.OpenFile(draftPath, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		die("Draft unavailable")
	}
	st, err := f.Stat()
	if err != nil || !st.Mode().IsRegular() || st.Mode().Perm() != 0600 || st.Size() > 1024*1024 {
		f.Close()
		die("Draft must be a private file under 1 MiB")
	}
	b, err := io.ReadAll(f)
	f.Close()
	if err != nil {
		die("Cannot read draft")
	}
	var input struct {
		Kind  string   `json:"kind"`
		Title string   `json:"title"`
		Text  string   `json:"text"`
		Items []string `json:"items"`
	}
	if json.Unmarshal(b, &input) != nil {
		die("Invalid note draft")
	}
	if input.Kind == "" {
		input.Kind = "text"
	} // Existing private drafts predate list creation.
	if (input.Kind != "text" && input.Kind != "checklist") || len(input.Items) > 1000 {
		die("Invalid note kind or item count")
	}
	c := loadCache(p)
	cred := getCredential(p)
	if realm := capabilities(p, cred); realm != p.Realm {
		die("Realm changed; write blocked")
	}
	noteID := id("note_")
	requestID := id("req_")
	var body []byte
	if input.Kind == "text" {
		body, _ = json.Marshal(struct {
			DeviceID  string `json:"deviceId"`
			RequestID string `json:"requestId"`
			Kind      string `json:"kind"`
			Title     string `json:"title"`
			Text      string `json:"text"`
		}{p.DeviceID, requestID, "text", input.Title, input.Text})
	} else {
		items := make([]initialItem, 0, len(input.Items))
		for _, text := range input.Items {
			if text != "" {
				items = append(items, initialItem{ID: id("item_"), Text: text})
			}
		}
		body, _ = json.Marshal(struct {
			DeviceID  string        `json:"deviceId"`
			RequestID string        `json:"requestId"`
			Kind      string        `json:"kind"`
			Title     string        `json:"title"`
			Items     []initialItem `json:"items"`
		}{p.DeviceID, requestID, "checklist", input.Title, items})
	}
	m := mutation{State: "prepared", Realm: c.Realm, TokenID: p.TokenID, DeviceID: p.DeviceID, RequestID: requestID, Method: "PUT", Path: "/api/v2/notes/" + noteID, Body: body, Draft: draftPath}
	if err = save("mutation.json", m); err != nil {
		die("Could not durably prepare note")
	}
	send(p, cred, m)
}
func setChecked(noteID, itemID, revision, value string) {
	if !validID(noteID) || !validID(itemID) || !validDecimal(revision) || (value != "true" && value != "false") {
		die("Invalid checklist assignment")
	}
	p := loadProfile()
	if _, ok := journal(); ok {
		die("Resolve the previous write before changing another item")
	}
	c := loadCache(p)
	var n note
	if json.Unmarshal(c.Resources["note:"+noteID], &n) != nil || n.ID != noteID || n.Kind != "checklist" || n.State != "live" {
		die("Live checklist not found in the local cache")
	}
	found := false
	for _, item := range n.Items {
		if item.ID == itemID && !item.Deleted {
			if !validDecimal(item.Revision) || item.Revision != revision {
				die("Item changed; refresh the list before trying again")
			}
			if item.Checked == (value == "true") {
				die("Item is already in that state; refresh the list")
			}
			found = true
			break
		}
	}
	if !found {
		die("Checklist item not found")
	}
	cred := getCredential(p)
	if capabilities(p, cred) != p.Realm {
		die("Realm changed; write blocked")
	}
	requestID := id("req_")
	body, _ := json.Marshal(struct {
		DeviceID         string `json:"deviceId"`
		RequestID        string `json:"requestId"`
		ExpectedRevision string `json:"expectedRevision"`
		Checked          bool   `json:"checked"`
	}{p.DeviceID, requestID, revision, value == "true"})
	m := mutation{State: "prepared", Realm: c.Realm, TokenID: p.TokenID, DeviceID: p.DeviceID, RequestID: requestID, Method: "PATCH", Path: "/api/v2/notes/" + noteID + "/items/" + itemID + "/checked", Body: body}
	if err := save("mutation.json", m); err != nil {
		die("Could not durably prepare checklist assignment")
	}
	send(p, cred, m)
}
func retry() {
	p := loadProfile()
	m, ok := journal()
	if !ok || m.State != "unknown" {
		die("No unknown write to retry")
	}
	cred := getCredential(p)
	if p.Realm != m.Realm || p.TokenID != m.TokenID || p.DeviceID != m.DeviceID || capabilities(p, cred) != p.Realm {
		die("Realm or credential changed; exact retry blocked")
	}
	send(p, cred, m)
}
func send(p profile, cred string, m mutation) {
	m.State = "sending"
	if err := save("mutation.json", m); err != nil {
		die("Could not persist sending state")
	}
	code, b, err := request(p, cred, m.Method, m.Path, m.Body)
	if err != nil {
		m.State = "unknown"
		_ = save("mutation.json", m)
		die("Write outcome unknown. Use Retry exact request; do not create a replacement")
	}
	if code == 200 {
		var receipt struct {
			ResourceType string `json:"resourceType"`
			ResourceID   string `json:"resourceId"`
			Revision     string `json:"revision"`
		}
		if json.Unmarshal(b, &receipt) == nil && receipt.ResourceType == "note" && receipt.ResourceID == mutationNoteID(m.Path) && validDecimal(receipt.Revision) {
			if err := remove("mutation.json"); err != nil {
				die("Note saved, but journal cleanup failed; do not create another note")
			}
			if m.Draft != "" {
				_ = os.Remove(m.Draft)
			}
			saved := envelope{OK: true, State: "saved"}
			if m.Method == "PATCH" {
				saved.NoteID = mutationNoteID(m.Path)
			}
			result(saved)
			return
		}
	}
	if code == 409 {
		m.State = "conflict"
		if save("mutation.json", m) != nil {
			die("Conflict; could not persist evidence")
		}
		die("This write conflicted with another change; review it in Nodus Web")
	}
	if code == 400 || code == 401 || code == 403 || code == 404 || code == 405 || code == 413 || code == 415 {
		var api apiError
		if json.Unmarshal(b, &api) == nil && api.Code != "" {
			if remove("mutation.json") != nil {
				die("Write rejected; journal cleanup failed")
			}
			die("Write rejected (" + api.Code + "); local draft retained if this was a new note")
		}
	}
	m.State = "unknown"
	_ = save("mutation.json", m)
	die("Write outcome unknown (HTTP " + fmt.Sprint(code) + "). Use Retry exact request")
}
func status() {
	p := loadProfile()
	getCredential(p)
	m, ok := journal()
	state := "ready"
	if ok {
		state = m.State
	}
	result(envelope{OK: true, State: state, Origin: p.Origin})
}
