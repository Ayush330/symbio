package transport

import (
	"encoding/json"
	"net/http"
)

// Response is a standard success response wrapper (optional, but good for future consistency)
type Response struct {
	Data interface{} `json:"data,omitempty"`
}

// ErrorResponse is the standard error response format
type ErrorResponse struct {
	Error string `json:"error"`
}

// WriteJSON sends a JSON response with the given status code
func WriteJSON(w http.ResponseWriter, code int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	if data != nil {
		json.NewEncoder(w).Encode(data)
	}
}

// SendError sends a standardized JSON error response
func SendError(w http.ResponseWriter, code int, message string) {
	WriteJSON(w, code, ErrorResponse{Error: message})
}
