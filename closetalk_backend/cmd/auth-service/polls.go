package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/go-chi/chi/v5"
)

type createPollRequest struct {
	ChatID         string   `json:"chat_id"`
	Question       string   `json:"question"`
	Options        []string `json:"options"`
	MultipleChoice bool     `json:"multiple_choice"`
}

func handleCreatePoll(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req createPollRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.ChatID == "" || req.Question == "" || len(req.Options) < 2 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "chat_id, question, and at least 2 options required"})
		return
	}
	if len(req.Options) > 10 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "max 10 options allowed"})
		return
	}

	optionsJSON, _ := json.Marshal(req.Options)

	ctx := context.Background()
	var pollID string
	err := database.Pool.QueryRow(ctx,
		`INSERT INTO polls (chat_id, creator_id, question, options, multiple_choice)
		 VALUES ($1, $2, $3, $4, $5) RETURNING id`,
		req.ChatID, userID, req.Question, string(optionsJSON), req.MultipleChoice,
	).Scan(&pollID)
	if err != nil {
		log.Printf("[polls] create error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to create poll"})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{"id": pollID})
}

func handleVotePoll(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	pollID := chi.URLParam(r, "id")

	var req struct {
		OptionIndex int `json:"option_index"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	ctx := context.Background()

	var isClosed bool
	err := database.Pool.QueryRow(ctx,
		`SELECT is_closed FROM polls WHERE id = $1`, pollID,
	).Scan(&isClosed)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "poll not found"})
		return
	}
	if isClosed {
		writeError(w, http.StatusConflict, &model.AppError{Code: "POLL_CLOSED", Message: "poll is closed"})
		return
	}

	var rawOptions string
	err = database.Pool.QueryRow(ctx,
		`SELECT options::text FROM polls WHERE id = $1`, pollID,
	).Scan(&rawOptions)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "poll not found"})
		return
	}

	var options []string
	json.Unmarshal([]byte(rawOptions), &options)
	if req.OptionIndex < 0 || req.OptionIndex >= len(options) {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "invalid option index"})
		return
	}

	_, err = database.Pool.Exec(ctx,
		`INSERT INTO poll_votes (poll_id, user_id, option_index) VALUES ($1, $2, $3)
		 ON CONFLICT (poll_id, user_id) DO UPDATE SET option_index = $3, voted_at = now()`,
		pollID, userID, req.OptionIndex,
	)
	if err != nil {
		log.Printf("[polls] vote error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to vote"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "voted"})
}

func handleGetPollResults(w http.ResponseWriter, r *http.Request) {
	pollID := chi.URLParam(r, "id")

	ctx := context.Background()
	var question, rawOptions string
	var isClosed bool
	var chatID string
	err := database.Pool.QueryRow(ctx,
		`SELECT chat_id, question, options::text, is_closed FROM polls WHERE id = $1`,
		pollID,
	).Scan(&chatID, &question, &rawOptions, &isClosed)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "poll not found"})
		return
	}

	var options []string
	json.Unmarshal([]byte(rawOptions), &options)

	voteCounts := make([]int, len(options))
	totalVotes := 0

	rows, err := database.Pool.Query(ctx,
		`SELECT option_index, COUNT(*) as cnt FROM poll_votes WHERE poll_id = $1 GROUP BY option_index`,
		pollID,
	)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var idx, cnt int
			rows.Scan(&idx, &cnt)
			if idx >= 0 && idx < len(voteCounts) {
				voteCounts[idx] = cnt
				totalVotes += cnt
			}
		}
	}

	type optionResult struct {
		Text  string  `json:"text"`
		Votes int     `json:"votes"`
		Pct   float64 `json:"pct"`
	}
	results := []optionResult{}
	for i, opt := range options {
		pct := 0.0
		if totalVotes > 0 {
			pct = float64(voteCounts[i]) / float64(totalVotes) * 100
		}
		results = append(results, optionResult{
			Text:  opt,
			Votes: voteCounts[i],
			Pct:   pct,
		})
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"poll_id":     pollID,
		"chat_id":     chatID,
		"question":    question,
		"options":     results,
		"total_votes": totalVotes,
		"is_closed":   isClosed,
	})
}
