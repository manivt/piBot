package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os/exec"
	"strings"
	"time"
)

const (
	listenAddr        = "127.0.0.1:8088"
	heartbeatInterval = 30 * time.Second
	maxLogFieldChars  = 4000
)

type Message struct {
	Role    string `json:"role"`
	Content any    `json:"content"`
}

type ChatRequest struct {
	Model    string    `json:"model"`
	Messages []Message `json:"messages"`
}

type ChatResponse struct {
	ID      string   `json:"id"`
	Object  string   `json:"object"`
	Created int64    `json:"created"`
	Model   string   `json:"model"`
	Choices []Choice `json:"choices"`
}

type Choice struct {
	Index        int             `json:"index"`
	Message      ResponseMessage `json:"message"`
	FinishReason string          `json:"finish_reason"`
}

type ResponseMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type DeniedAction struct {
	Action      string `json:"action"`
	DisplayName string `json:"display_name"`
}

type AgyResponse struct {
	ConversationID  string         `json:"conversation_id"`
	Status          string         `json:"status"`
	Response        string         `json:"response"`
	Error           string         `json:"error"`
	DurationSeconds float64        `json:"duration_seconds"`
	NumTurns        int            `json:"num_turns"`
	Usage           AgyUsage       `json:"usage"`
	DeniedActions   []DeniedAction `json:"denied_actions"`
}

type AgyUsage struct {
	InputTokens     int `json:"input_tokens"`
	OutputTokens    int `json:"output_tokens"`
	ThinkingTokens  int `json:"thinking_tokens"`
	CacheReadTokens int `json:"cache_read_tokens"`
	TotalTokens     int `json:"total_tokens"`
}

func contentToString(v any) string {
	switch x := v.(type) {
	case string:
		return x
	case nil:
		return ""
	default:
		b, err := json.Marshal(x)
		if err != nil {
			return ""
		}
		return string(b)
	}
}

func buildPrompt(messages []Message) string {
	var b strings.Builder

	for _, m := range messages {
		content := strings.TrimSpace(contentToString(m.Content))
		if content == "" {
			continue
		}

		fmt.Fprintf(
			&b,
			"%s:\n%s\n\n",
			strings.ToUpper(m.Role),
			content,
		)
	}

	b.WriteString("Respond to the user's latest request.")
	return b.String()
}

func mapModel(requested string) string {
	switch requested {
	case "agy-gemini-high":
		return "gemini-3.8-flash-high"
	case "agy-sonnet":
		return "claude-sonnet-4-6"
	case "agy-opus":
		return "claude-opus-4-6-thinking"
	case "agy-gemini-medium", "":
		return "gemini-3.8-flash-medium"
	default:
		return "gemini-3.8-flash-medium"
	}
}

func truncateForLog(s string, maxChars int) string {
	s = strings.TrimSpace(s)
	if len(s) <= maxChars {
		return s
	}
	return s[:maxChars] + "...[truncated]"
}

func deniedActionsForLog(actions []DeniedAction) string {
	if len(actions) == 0 {
		return "[]"
	}

	b, err := json.Marshal(actions)
	if err != nil {
		return fmt.Sprintf("[marshal error: %v]", err)
	}
	return truncateForLog(string(b), maxLogFieldChars)
}

func runAgy(
	ctx context.Context,
	requestID string,
	prompt string,
	model string,
) (string, AgyResponse, time.Duration, error) {
	// No independent --print-timeout is used here.
	// The agy process inherits the HTTP request context, so the upstream
	// ZeroClaw provider timeout/client cancellation is the controlling timeout.
	cmd := exec.CommandContext(
		ctx,
		"agy",
		"-p", prompt,
		"--model", model,
		"--output-format", "json",
		"--dangerously-skip-permissions",
	)

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	start := time.Now()

	log.Printf(
		"request_id=%s agy_start model=%s prompt_chars=%d",
		requestID,
		model,
		len(prompt),
	)

	done := make(chan struct{})
	go func() {
		ticker := time.NewTicker(heartbeatInterval)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				log.Printf(
					"request_id=%s agy_running model=%s prompt_chars=%d elapsed=%s",
					requestID,
					model,
					len(prompt),
					time.Since(start).Round(time.Second),
				)
			case <-ctx.Done():
				return
			case <-done:
				return
			}
		}
	}()

	err := cmd.Run()
	close(done)

	duration := time.Since(start)
	stdoutBytes := stdout.Len()
	stderrBytes := stderr.Len()

	log.Printf(
		"request_id=%s agy_process_end model=%s elapsed=%s stdout_bytes=%d stderr_bytes=%d process_error=%t",
		requestID,
		model,
		duration.Round(time.Millisecond),
		stdoutBytes,
		stderrBytes,
		err != nil,
	)

	var agyResp AgyResponse

	// agy may still return a structured JSON envelope on stdout even when the
	// process exits non-zero, so decode stdout before interpreting the exit.
	if stdoutBytes > 0 {
		if jsonErr := json.Unmarshal(stdout.Bytes(), &agyResp); jsonErr != nil {
			log.Printf(
				"request_id=%s agy_invalid_json model=%s elapsed=%s process_error=%v json_error=%v stdout_tail=%q stderr_tail=%q",
				requestID,
				model,
				duration.Round(time.Millisecond),
				err,
				jsonErr,
				truncateForLog(stdout.String(), maxLogFieldChars),
				truncateForLog(stderr.String(), maxLogFieldChars),
			)

			if err != nil {
				return "", agyResp, duration, fmt.Errorf(
					"agy process failed: %w; stderr=%q; invalid JSON=%v",
					err,
					truncateForLog(stderr.String(), maxLogFieldChars),
					jsonErr,
				)
			}

			return "", agyResp, duration, fmt.Errorf(
				"agy returned invalid JSON: %w",
				jsonErr,
			)
		}
	}

	log.Printf(
		"request_id=%s agy_envelope model=%s conversation_id=%q status=%q num_turns=%d agy_duration_seconds=%.3f denied_actions=%d",
		requestID,
		model,
		agyResp.ConversationID,
		agyResp.Status,
		agyResp.NumTurns,
		agyResp.DurationSeconds,
		len(agyResp.DeniedActions),
	)

	if err != nil {
		if ctx.Err() != nil {
			log.Printf(
				"request_id=%s agy_context_end model=%s elapsed=%s context_error=%q stderr_tail=%q",
				requestID,
				model,
				duration.Round(time.Millisecond),
				ctx.Err(),
				truncateForLog(stderr.String(), maxLogFieldChars),
			)
			return "", agyResp, duration, ctx.Err()
		}

		var exitErr *exec.ExitError
		exitCode := -1
		if errors.As(err, &exitErr) {
			exitCode = exitErr.ExitCode()
		}

		log.Printf(
			"request_id=%s agy_process_error model=%s elapsed=%s exit_code=%d status=%q agy_error=%q denied_actions=%s stderr_tail=%q",
			requestID,
			model,
			duration.Round(time.Millisecond),
			exitCode,
			agyResp.Status,
			agyResp.Error,
			deniedActionsForLog(agyResp.DeniedActions),
			truncateForLog(stderr.String(), maxLogFieldChars),
		)

		return "", agyResp, duration, fmt.Errorf(
			"agy process failed: %w; status=%q error=%q stderr=%q",
			err,
			agyResp.Status,
			agyResp.Error,
			truncateForLog(stderr.String(), maxLogFieldChars),
		)
	}

	if strings.ToUpper(agyResp.Status) != "SUCCESS" {
		log.Printf(
			"request_id=%s agy_non_success model=%s elapsed=%s status=%q agy_error=%q denied_actions=%s stderr_tail=%q",
			requestID,
			model,
			duration.Round(time.Millisecond),
			agyResp.Status,
			agyResp.Error,
			deniedActionsForLog(agyResp.DeniedActions),
			truncateForLog(stderr.String(), maxLogFieldChars),
		)

		return "", agyResp, duration, fmt.Errorf(
			"agy returned status=%q error=%q",
			agyResp.Status,
			agyResp.Error,
		)
	}

	text := strings.TrimSpace(agyResp.Response)
	if text == "" {
		// This is an important diagnostic case: agy has sometimes returned
		// status=SUCCESS with no final response after doing substantial work.
		log.Printf(
			"request_id=%s agy_empty_response model=%s elapsed=%s conversation_id=%q status=%q agy_error=%q turns=%d input_tokens=%d output_tokens=%d thinking_tokens=%d cache_read_tokens=%d total_tokens=%d denied_actions=%s stderr_tail=%q raw_json=%q",
			requestID,
			model,
			duration.Round(time.Millisecond),
			agyResp.ConversationID,
			agyResp.Status,
			agyResp.Error,
			agyResp.NumTurns,
			agyResp.Usage.InputTokens,
			agyResp.Usage.OutputTokens,
			agyResp.Usage.ThinkingTokens,
			agyResp.Usage.CacheReadTokens,
			agyResp.Usage.TotalTokens,
			deniedActionsForLog(agyResp.DeniedActions),
			truncateForLog(stderr.String(), maxLogFieldChars),
			truncateForLog(stdout.String(), maxLogFieldChars),
		)

		return "", agyResp, duration, fmt.Errorf(
			"agy returned SUCCESS with an empty response",
		)
	}

	return text, agyResp, duration, nil
}

func chatCompletions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	requestID := fmt.Sprintf("%d", time.Now().UnixNano())
	requestStart := time.Now()

	// Protect the Pi from unexpectedly large requests.
	r.Body = http.MaxBytesReader(w, r.Body, 4<<20) // 4 MiB

	var req ChatRequest

	decoder := json.NewDecoder(r.Body)
	if err := decoder.Decode(&req); err != nil {
		log.Printf(
			"request_id=%s request_rejected reason=invalid_json detail=%v",
			requestID,
			err,
		)
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	if len(req.Messages) == 0 {
		log.Printf(
			"request_id=%s request_rejected reason=no_messages",
			requestID,
		)
		http.Error(w, "messages are required", http.StatusBadRequest)
		return
	}

	prompt := buildPrompt(req.Messages)
	model := mapModel(req.Model)

	log.Printf(
		"request_id=%s request_received requested_model=%q mapped_model=%s messages=%d prompt_chars=%d content_length=%d",
		requestID,
		req.Model,
		model,
		len(req.Messages),
		len(prompt),
		r.ContentLength,
	)

	// Deliberately do not add another independent timeout here.
	// When ZeroClaw times out/cancels the HTTP request, r.Context() is canceled
	// and exec.CommandContext terminates the agy child process.
	text, agyResp, duration, err := runAgy(r.Context(), requestID, prompt, model)

	if err != nil {
		switch {
		case errors.Is(err, context.DeadlineExceeded):
			log.Printf(
				"request_id=%s request_timeout model=%s prompt_chars=%d agy_duration=%s total_elapsed=%s",
				requestID,
				model,
				len(prompt),
				duration.Round(time.Millisecond),
				time.Since(requestStart).Round(time.Millisecond),
			)
			http.Error(w, "agy request timed out", http.StatusGatewayTimeout)
			return

		case errors.Is(err, context.Canceled):
			log.Printf(
				"request_id=%s request_canceled model=%s prompt_chars=%d agy_duration=%s total_elapsed=%s",
				requestID,
				model,
				len(prompt),
				duration.Round(time.Millisecond),
				time.Since(requestStart).Round(time.Millisecond),
			)
			return

		default:
			log.Printf(
				"request_id=%s request_error model=%s prompt_chars=%d agy_duration=%s total_elapsed=%s conversation_id=%q status=%q agy_error=%q detail=%v",
				requestID,
				model,
				len(prompt),
				duration.Round(time.Millisecond),
				time.Since(requestStart).Round(time.Millisecond),
				agyResp.ConversationID,
				agyResp.Status,
				agyResp.Error,
				err,
			)

			http.Error(w, "agy request failed", http.StatusBadGateway)
			return
		}
	}

	log.Printf(
		"request_id=%s agy_success model=%s prompt_chars=%d duration=%s conversation_id=%q turns=%d input_tokens=%d output_tokens=%d thinking_tokens=%d cache_read_tokens=%d total_tokens=%d response_chars=%d",
		requestID,
		model,
		len(prompt),
		duration.Round(time.Millisecond),
		agyResp.ConversationID,
		agyResp.NumTurns,
		agyResp.Usage.InputTokens,
		agyResp.Usage.OutputTokens,
		agyResp.Usage.ThinkingTokens,
		agyResp.Usage.CacheReadTokens,
		agyResp.Usage.TotalTokens,
		len(text),
	)

	now := time.Now()

	responseModel := req.Model
	if responseModel == "" {
		responseModel = "agy-gemini-medium"
	}

	resp := ChatResponse{
		ID:      fmt.Sprintf("agy-%d", now.UnixNano()),
		Object:  "chat.completion",
		Created: now.Unix(),
		Model:   responseModel,
		Choices: []Choice{
			{
				Index: 0,
				Message: ResponseMessage{
					Role:    "assistant",
					Content: text,
				},
				FinishReason: "stop",
			},
		},
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(resp); err != nil {
		log.Printf(
			"request_id=%s response_encoding_error detail=%v",
			requestID,
			err,
		)
		return
	}

	log.Printf(
		"request_id=%s request_complete model=%s total_elapsed=%s",
		requestID,
		model,
		time.Since(requestStart).Round(time.Millisecond),
	)
}

func health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/health", health)
	mux.HandleFunc("/v1/chat/completions", chatCompletions)

	server := &http.Server{
		Addr:              listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,

		// No independent response deadline here. ZeroClaw's provider timeout is
		// intended to be the controlling request deadline for long-running agy
		// work such as builds and pytest. The server only listens on loopback.
		WriteTimeout: 0,

		IdleTimeout: 60 * time.Second,
	}

	log.Printf(
		"agy shim listening on http://%s heartbeat_interval=%s write_timeout=disabled",
		listenAddr,
		heartbeatInterval,
	)

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
