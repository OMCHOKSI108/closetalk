package middleware

import (
	"context"
	"net/http"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/database"
)

type RateLimitConfig struct {
	Limit  int
	Window time.Duration
	KeyFn  func(r *http.Request) string
}

func RateLimit(cfg RateLimitConfig) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := cfg.KeyFn(r)
			allowed, err := database.CheckRateLimit(context.Background(), key, cfg.Limit, cfg.Window)
			if err != nil || !allowed {
				w.Header().Set("Retry-After", "60")
				http.Error(w, `{"error":"rate limited","code":"RATE_LIMITED"}`, http.StatusTooManyRequests)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func UserRateLimit(next http.Handler) http.Handler {
	return RateLimit(RateLimitConfig{
		Limit:  100,
		Window: time.Minute,
		KeyFn: func(r *http.Request) string {
			userID, _ := r.Context().Value(UserIDKey).(string)
			return "ratelimit:user:" + userID
		},
	})(next)
}

func IPRateLimit(next http.Handler) http.Handler {
	return RateLimit(RateLimitConfig{
		Limit:  1000,
		Window: time.Minute,
		KeyFn: func(r *http.Request) string {
			ip := r.Header.Get("X-Forwarded-For")
			if ip == "" {
				ip = r.RemoteAddr
			}
			return "ratelimit:ip:" + ip
		},
	})(next)
}
