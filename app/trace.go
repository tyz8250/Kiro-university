package main

import (
	"regexp"

	"github.com/google/uuid"
)

// TraceID はリクエストを追跡するためのID
// パターン: ^[A-Za-z0-9\-_]{1,64}$
// 有効: 1〜64文字、[A-Za-z0-9\-_] のみ
// 無効: 65文字以上、または [A-Za-z0-9\-_] 以外の文字を含む
type TraceID string

const (
	// TraceIDMaxLen はTraceIDの最大文字数
	// 65文字以上はすべて invalid
	TraceIDMaxLen = 64

	// TraceIDPattern はTraceIDの正規表現パターン
	TraceIDPattern = `^[A-Za-z0-9\-_]{1,64}$`
)

// traceIDRegex はTraceIDパターンのコンパイル済み正規表現
var traceIDRegex = regexp.MustCompile(TraceIDPattern)

// Validate はTraceIDの形式を検証する
// 有効（1〜64文字かつパターン一致）: true
// 無効（空文字、65文字以上、パターン外文字を含む）: false
func (t TraceID) Validate() bool {
	// 空文字は invalid
	if t == "" {
		return false
	}

	// 65文字以上（最大64文字超）は invalid
	if len(t) > TraceIDMaxLen {
		return false
	}

	// パターン不一致は invalid
	return traceIDRegex.MatchString(string(t))
}

// NewTraceID はUUID v4ベースの新しいTraceIDを生成する
func NewTraceID() TraceID {
	return TraceID(uuid.New().String())
}
