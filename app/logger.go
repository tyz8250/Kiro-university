package main

import (
	"encoding/json"
	"io"
	"os"
	"time"
)

// LogEntry はHTTPリクエストの構造化ログエントリ
type LogEntry struct {
	Timestamp  time.Time `json:"timestamp"`
	TraceID    TraceID   `json:"trace_id"`
	Method     string    `json:"method"`
	Path       string    `json:"path"`
	Status     int       `json:"status"`
	DurationMs int64     `json:"duration_ms"`
}

// Logger はログ出力インターフェース
type Logger interface {
	WriteLog(e LogEntry)
}

// defaultLogger はデフォルトのロガー（標準出力に出力）
type defaultLogger struct {
	w io.Writer
}

func (d defaultLogger) WriteLog(e LogEntry) {
	encoder := json.NewEncoder(d.w)
	encoder.Encode(e)
}

// logWriter はグローバルなLoggerインターフェース
var logWriter Logger = defaultLogger{w: os.Stdout}

// SetLogger はテスト用のロガーを設定する（テスト用）
func SetLogger(l Logger) {
	logWriter = l
}

// WriteLog はLogEntryをJSON形式で標準出力に書き出す
func WriteLog(w io.Writer, e LogEntry) {
	encoder := json.NewEncoder(w)
	encoder.Encode(e)
}
