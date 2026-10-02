#!/usr/bin/env bash

set -euo pipefail

readonly SSH_USER="ec2-user"
readonly CONTAINER_NAME="go-server"
readonly TCPDUMP_PACKET_LIMIT=20
readonly TCPDUMP_TIMEOUT_SECONDS=15

usage() {
  echo "Usage: $0 EC2_PUBLIC_IP EC2_KEY_PATH" >&2
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

http_status_from_output() {
  sed -n 's/^__HTTP_STATUS__://p' | tail -n 1
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

readonly EC2_PUBLIC_IP="$1"
readonly EC2_KEY_PATH="$2"

if [[ ! -f "$EC2_KEY_PATH" || ! -r "$EC2_KEY_PATH" ]]; then
  echo "EC2 key is not a readable file: $EC2_KEY_PATH" >&2
  exit 2
fi

if [[ ! "$EC2_PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "EC2_PUBLIC_IP must be an IPv4 address: $EC2_PUBLIC_IP" >&2
  exit 2
fi

IFS=. read -r ip1 ip2 ip3 ip4 <<<"$EC2_PUBLIC_IP"
for octet in "$ip1" "$ip2" "$ip3" "$ip4"; do
  if ((10#$octet > 255)); then
    echo "EC2_PUBLIC_IP contains an invalid octet: $EC2_PUBLIC_IP" >&2
    exit 2
  fi
done

for required_command in ssh curl jq uuidgen mktemp grep sed tail tr date; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command not found: $required_command" >&2
    exit 1
  fi
done

TRACE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
readonly TRACE_ID
if [[ ! "$TRACE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
  echo "uuidgen did not return a UUID v4: $TRACE_ID" >&2
  exit 1
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly RESULTS_DIR="$PROJECT_ROOT/results"
readonly OUTPUT_PATH="$RESULTS_DIR/baseline.json"
readonly SSH_TARGET="$SSH_USER@$EC2_PUBLIC_IP"
readonly CAPTURED_AT="$(timestamp_utc)"

SSH_OPTIONS=(
  -i "$EC2_KEY_PATH"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

if ! ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" true; then
  echo "Unable to connect to $SSH_TARGET over SSH" >&2
  exit 1
fi

if ! ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" \
  "command -v ip >/dev/null && command -v curl >/dev/null && command -v docker >/dev/null && command -v tcpdump >/dev/null && command -v timeout >/dev/null && sudo -n true"; then
  echo "EC2 is missing a required command or passwordless sudo access" >&2
  exit 1
fi

REMOTE_IFACE=$(ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" \
  "ip route show default | awk '{print \$5; exit}'")
readonly REMOTE_IFACE
if [[ ! "$REMOTE_IFACE" =~ ^[[:alnum:]_.:-]+$ ]]; then
  echo "Could not determine a safe EC2 network interface: $REMOTE_IFACE" >&2
  exit 1
fi

TCPDUMP_TMP=$(mktemp "${TMPDIR:-/tmp}/network-fault-baseline.XXXXXX")
TCPDUMP_SSH_PID=""

cleanup() {
  if [[ -n "$TCPDUMP_SSH_PID" ]] && kill -0 "$TCPDUMP_SSH_PID" 2>/dev/null; then
    kill "$TCPDUMP_SSH_PID" 2>/dev/null || true
    wait "$TCPDUMP_SSH_PID" 2>/dev/null || true
  fi
  rm -f "$TCPDUMP_TMP"
}
trap cleanup EXIT

TCPDUMP_TIMESTAMP=$(timestamp_utc)
ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" \
  "sudo -n timeout $TCPDUMP_TIMEOUT_SECONDS tcpdump -nn -tttt -i '$REMOTE_IFACE' 'tcp port 8080' -c $TCPDUMP_PACKET_LIMIT" \
  >"$TCPDUMP_TMP" 2>&1 &
TCPDUMP_SSH_PID=$!

# tcpdumpが起動してから外部リクエストを送る。
sleep 1

MAC_CURL_TIMESTAMP=$(timestamp_utc)
MAC_CURL_SUCCESS=false
if MAC_CURL_RESULT=$(curl --silent --show-error --include --max-time 10 \
  -H "X-Trace-ID: $TRACE_ID" \
  --write-out $'\n__HTTP_STATUS__:%{http_code}\n' \
  "http://$EC2_PUBLIC_IP:8080/health" 2>&1); then
  MAC_HTTP_STATUS=$(printf '%s\n' "$MAC_CURL_RESULT" | http_status_from_output)
  if [[ "$MAC_HTTP_STATUS" == "200" ]]; then
    MAC_CURL_SUCCESS=true
  fi
fi

DOCKER_PS_TIMESTAMP=$(timestamp_utc)
DOCKER_PS_SUCCESS=false
if DOCKER_PS_RESULT=$(ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" \
  "docker ps --filter 'name=^/$CONTAINER_NAME$' --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'" 2>&1); then
  if grep -Fq "$CONTAINER_NAME" <<<"$DOCKER_PS_RESULT"; then
    DOCKER_PS_SUCCESS=true
  fi
fi

HOST_CURL_TIMESTAMP=$(timestamp_utc)
HOST_CURL_SUCCESS=false
if HOST_CURL_RESULT=$(ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" \
  "curl --silent --show-error --include --max-time 10 -H 'X-Trace-ID: $TRACE_ID' --write-out '\\n__HTTP_STATUS__:%{http_code}\\n' http://localhost:8080/health" 2>&1); then
  HOST_HTTP_STATUS=$(printf '%s\n' "$HOST_CURL_RESULT" | http_status_from_output)
  if [[ "$HOST_HTTP_STATUS" == "200" ]]; then
    HOST_CURL_SUCCESS=true
  fi
fi

# レスポンス後にアプリの構造化ログが出力される時間を確保する。
sleep 1

GO_LOG_TIMESTAMP=$(timestamp_utc)
GO_LOG_SUCCESS=false
if GO_LOG_RESULT=$(ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" \
  "docker logs --timestamps --tail 50 '$CONTAINER_NAME' 2>&1" 2>&1); then
  if grep -Fq "$TRACE_ID" <<<"$GO_LOG_RESULT"; then
    GO_LOG_SUCCESS=true
  fi
fi

if wait "$TCPDUMP_SSH_PID"; then
  TCPDUMP_EXIT=0
else
  TCPDUMP_EXIT=$?
fi
TCPDUMP_SSH_PID=""

TCPDUMP_OUTPUT=$(<"$TCPDUMP_TMP")
printf -v TCPDUMP_RESULT \
  'capture_started_at=%s\ninterface=%s\nfilter=tcp port 8080\ntrace_id_visibility=not visible at L4; correlate by timestamp, source IP, and destination port\n%s' \
  "$TCPDUMP_TIMESTAMP" "$REMOTE_IFACE" "$TCPDUMP_OUTPUT"

TCPDUMP_SUCCESS=false
if [[ "$TCPDUMP_EXIT" -eq 0 || "$TCPDUMP_EXIT" -eq 124 ]] && \
  grep -Eq '\.8080([:[:space:]]|$)' <<<"$TCPDUMP_OUTPUT"; then
  TCPDUMP_SUCCESS=true
fi

mkdir -p "$RESULTS_DIR"
jq -n \
  --arg phase "baseline" \
  --arg captured_at "$CAPTURED_AT" \
  --arg trace_id "$TRACE_ID" \
  --arg mac_timestamp "$MAC_CURL_TIMESTAMP" \
  --arg mac_result "$MAC_CURL_RESULT" \
  --argjson mac_success "$MAC_CURL_SUCCESS" \
  --arg tcpdump_timestamp "$TCPDUMP_TIMESTAMP" \
  --arg tcpdump_result "$TCPDUMP_RESULT" \
  --argjson tcpdump_success "$TCPDUMP_SUCCESS" \
  --arg docker_timestamp "$DOCKER_PS_TIMESTAMP" \
  --arg docker_result "$DOCKER_PS_RESULT" \
  --argjson docker_success "$DOCKER_PS_SUCCESS" \
  --arg host_timestamp "$HOST_CURL_TIMESTAMP" \
  --arg host_result "$HOST_CURL_RESULT" \
  --argjson host_success "$HOST_CURL_SUCCESS" \
  --arg log_timestamp "$GO_LOG_TIMESTAMP" \
  --arg log_result "$GO_LOG_RESULT" \
  --argjson log_success "$GO_LOG_SUCCESS" \
  '{
    phase: $phase,
    captured_at: $captured_at,
    points: [
      {
        name: "mac_curl",
        timestamp: $mac_timestamp,
        trace_id: $trace_id,
        result: $mac_result,
        success: $mac_success
      },
      {
        name: "tcpdump",
        timestamp: $tcpdump_timestamp,
        trace_id: "",
        result: $tcpdump_result,
        success: $tcpdump_success
      },
      {
        name: "docker_ps",
        timestamp: $docker_timestamp,
        trace_id: "",
        result: $docker_result,
        success: $docker_success
      },
      {
        name: "host_curl",
        timestamp: $host_timestamp,
        trace_id: $trace_id,
        result: $host_result,
        success: $host_success
      },
      {
        name: "go_server_logs",
        timestamp: $log_timestamp,
        trace_id: $trace_id,
        result: $log_result,
        success: $log_success
      }
    ]
  }' >"$OUTPUT_PATH"

if [[ "$MAC_CURL_SUCCESS" != true ||
      "$TCPDUMP_SUCCESS" != true ||
      "$DOCKER_PS_SUCCESS" != true ||
      "$HOST_CURL_SUCCESS" != true ||
      "$GO_LOG_SUCCESS" != true ]]; then
  echo "Baseline was recorded with one or more failed observation points: $OUTPUT_PATH" >&2
  exit 1
fi

echo "Baseline recorded: $OUTPUT_PATH"
