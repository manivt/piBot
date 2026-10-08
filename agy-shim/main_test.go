package main

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func TestBuildPromptKeepsSmallConversationIntact(t *testing.T) {
	prompt, dropped, err := buildPrompt([]Message{
		{Role: "system", Content: "be nice"},
		{Role: "user", Content: "hello"},
	})
	if err != nil || dropped != 0 {
		t.Fatalf("unexpected err=%v dropped=%d", err, dropped)
	}
	if !strings.Contains(prompt, "SYSTEM:\nbe nice") || !strings.Contains(prompt, "USER:\nhello") {
		t.Fatalf("prompt missing messages: %q", prompt)
	}
}

func TestBuildPromptDropsOldestHistoryToFitLimit(t *testing.T) {
	big := strings.Repeat("x", 50*1024)
	msgs := []Message{
		{Role: "system", Content: "SYSTEM PROMPT"},
		{Role: "user", Content: "old-1 " + big},
		{Role: "assistant", Content: "old-2 " + big},
		{Role: "user", Content: "old-3 " + big},
		{Role: "user", Content: "LATEST QUESTION"},
	}
	prompt, dropped, err := buildPrompt(msgs)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(prompt) > maxPromptBytes {
		t.Fatalf("prompt is %d bytes, limit %d", len(prompt), maxPromptBytes)
	}
	// 3 x 50 KiB of history against a 120 KiB limit: only the oldest must go.
	if dropped != 1 {
		t.Fatalf("expected 1 dropped message, got %d", dropped)
	}
	for _, want := range []string{"SYSTEM PROMPT", "LATEST QUESTION", "old-2", "old-3", "1 earlier messages omitted"} {
		if !strings.Contains(prompt, want) {
			t.Fatalf("prompt should contain %q", want)
		}
	}
	if strings.Contains(prompt, "old-1") {
		t.Fatal("oldest message should have been dropped")
	}
}

func TestBuildPromptErrorsWhenLatestMessageAloneIsTooLarge(t *testing.T) {
	_, _, err := buildPrompt([]Message{{Role: "user", Content: strings.Repeat("x", maxPromptBytes+1)}})
	if err != errPromptTooLarge {
		t.Fatalf("expected errPromptTooLarge, got %v", err)
	}
}

func TestAuthorized(t *testing.T) {
	shimToken = strings.Repeat("a", 64)
	cases := map[string]bool{
		"":                    false,
		"Bearer wrong":        false,
		"Basic " + shimToken:  false,
		"Bearer " + shimToken: true,
	}
	for header, want := range cases {
		r := httptest.NewRequest("POST", "/v1/chat/completions", nil)
		if header != "" {
			r.Header.Set("Authorization", header)
		}
		if got := authorized(r); got != want {
			t.Errorf("Authorization %q: got %v, want %v", header, got, want)
		}
	}
}

func TestListModelsRequiresAuthAndListsModels(t *testing.T) {
	shimToken = strings.Repeat("b", 64)

	rec := httptest.NewRecorder()
	listModels(rec, httptest.NewRequest("GET", "/v1/models", nil))
	if rec.Code != 401 {
		t.Fatalf("without token: got %d, want 401", rec.Code)
	}

	req := httptest.NewRequest("GET", "/v1/models", nil)
	req.Header.Set("Authorization", "Bearer "+shimToken)
	rec = httptest.NewRecorder()
	listModels(rec, req)
	if rec.Code != 200 || !strings.Contains(rec.Body.String(), `"id":"agy-gemini-medium"`) {
		t.Fatalf("with token: got %d %s", rec.Code, rec.Body.String())
	}
}

func TestListenPort(t *testing.T) {
	t.Setenv("AGY_SHIM_PORT", "")
	if p, err := listenPort(); err != nil || p != defaultPort {
		t.Fatalf("default: got %d, %v", p, err)
	}
	t.Setenv("AGY_SHIM_PORT", "9099")
	if p, err := listenPort(); err != nil || p != 9099 {
		t.Fatalf("custom: got %d, %v", p, err)
	}
	t.Setenv("AGY_SHIM_PORT", "nope")
	if _, err := listenPort(); err == nil {
		t.Fatal("expected error for invalid port")
	}
}
