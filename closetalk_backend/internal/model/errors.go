package model

type ErrorResponse struct {
	Error   string `json:"error"`
	Code    string `json:"code,omitempty"`
	Details any    `json:"details,omitempty"`
}

// Standard API errors
var (
	ErrInvalidRequest   = &AppError{Code: "INVALID_REQUEST", Message: "Invalid request body"}
	ErrEmailTaken       = &AppError{Code: "EMAIL_TAKEN", Message: "Email already registered"}
	ErrInvalidCredentials = &AppError{Code: "INVALID_CREDENTIALS", Message: "Invalid email or password"}
	ErrUserNotFound     = &AppError{Code: "USER_NOT_FOUND", Message: "User not found"}
	ErrInvalidToken     = &AppError{Code: "INVALID_TOKEN", Message: "Invalid or expired token"}
	ErrRateLimited      = &AppError{Code: "RATE_LIMITED", Message: "Too many requests, try again later"}
	ErrRecoveryCodeUsed = &AppError{Code: "RECOVERY_CODE_USED", Message: "Recovery code already used"}
	ErrRecoveryLimit    = &AppError{Code: "RECOVERY_LIMIT", Message: "Too many recovery attempts"}
)

type AppError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *AppError) Error() string {
	return e.Message
}
