package main

import (
	"context"
	"encoding/json"
	"net/http"
	"time"
)

// contextKey はコンテキストキーの型
type contextKey string

const traceIDKey contextKey = "trace_id"

// TraceIDMiddleware はリクエストのTrace IDを処理するミドルウェア
func TraceIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		startTime := time.Now()

		// X-Trace-ID ヘッダーからTrace IDを取得
		values := r.Header.Values("X-Trace-ID")
		var traceID TraceID

		if len(values) > 0 {
			// ヘッダーは存在する
			traceIDStr := values[0]
			traceID = TraceID(traceIDStr)

			if !traceID.Validate() {
				var errMsg string

				if traceIDStr == "" {
					errMsg = "trace_id must not be empty"
				} else if len(traceIDStr) > TraceIDMaxLen {
					errMsg = "trace_id exceeds maximum length of 64"
				} else {
					errMsg = "trace_id contains invalid characters: allowed [A-Za-z0-9-_]"
				}

				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusBadRequest)
				json.NewEncoder(w).Encode(map[string]string{"error": errMsg})
				return
			}
		} else {
			// ヘッダーそのものが存在しない
			traceID = NewTraceID()
		}

		// コンテキストにTrace IDを保存
		ctx := context.WithValue(r.Context(), traceIDKey, traceID)
		r = r.WithContext(ctx)

		// レスポンスヘッダーにX-Trace-IDを設定
		w.Header().Set("X-Trace-ID", string(traceID))

		// 次のハンドラーを呼び出し
		rr := &responseRecorder{ResponseWriter: w, statusCode: http.StatusOK}
		next.ServeHTTP(rr, r)

		// ログ出力
		durationMs := time.Since(startTime).Milliseconds()
		logEntry := LogEntry{
			Timestamp:  time.Now(),
			TraceID:    traceID,
			Method:     r.Method,
			Path:       r.URL.Path,
			Status:     rr.statusCode,
			DurationMs: durationMs,
		}
		logWriter.WriteLog(logEntry)
	})
}

// responseRecorder はレスポンスの状態をを記録するラッパー
type responseRecorder struct {
	http.ResponseWriter
	statusCode int
}

func (rr *responseRecorder) WriteHeader(code int) {
	rr.statusCode = code
	rr.ResponseWriter.WriteHeader(code)
}

// GetTraceID はコンテキストからTrace IDを取得する
func GetTraceID(ctx context.Context) TraceID {
	val := ctx.Value(traceIDKey)
	if id, ok := val.(TraceID); ok {
		return id
	}
	return ""
}

// HealthHandler は /health エンドポイントのハンドラー
func HealthHandler(w http.ResponseWriter, r *http.Request) {
	traceID := GetTraceID(r.Context())

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status":   "ok",
		"trace_id": string(traceID),
	})
}
