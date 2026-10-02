#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 EC2_PUBLIC_IP" >&2
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

http_status_from_output() {
  sed -n 's/^__HTTP_STATUS__://p' | tail -n 1
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

readonly EC2_PUBLIC_IP="$1"

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

for required_command in curl jq uuidgen mktemp sed tail tr date; do
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
readonly OUTPUT_PATH="$RESULTS_DIR/fault.json"
readonly CAPTURED_AT="$(timestamp_utc)"
readonly OBSERVED_AT="$(timestamp_utc)"

curl_exit_code=0
if CURL_OUTPUT=$(curl --silent --show-error --include \
  --connect-timeout 5 \
  --max-time 15 \
  -H "X-Trace-ID: $TRACE_ID" \
  --write-out $'\n__HTTP_STATUS__:%{http_code}\n' \
  "http://$EC2_PUBLIC_IP:8080/health" 2>&1); then
  curl_exit_code=0
else
  curl_exit_code=$?
fi

HTTP_STATUS=$(printf '%s\n' "$CURL_OUTPUT" | http_status_from_output)
HTTP_STATUS=${HTTP_STATUS:-000}

case "$curl_exit_code" in
  0)
    if [[ "$HTTP_STATUS" == "200" ]]; then
      outcome="http_200"
    else
      outcome="http_status"
    fi
    ;;
  7)
    outcome="connection_error"
    ;;
  28)
    outcome="timeout"
    ;;
  *)
    outcome="curl_error"
    ;;
esac

CURL_SUCCESS=false
if [[ "$curl_exit_code" -eq 0 && "$HTTP_STATUS" == "200" ]]; then
  CURL_SUCCESS=true
fi

printf -v OBSERVATION_RESULT \
  'observed_at=%s\noutcome=%s\ncurl_exit_code=%s\nhttp_status=%s\n%s' \
  "$OBSERVED_AT" "$outcome" "$curl_exit_code" "$HTTP_STATUS" "$CURL_OUTPUT"

mkdir -p "$RESULTS_DIR"
output_tmp=$(mktemp "$RESULTS_DIR/.fault.json.XXXXXX")

cleanup() {
  if [[ -n "${output_tmp:-}" && -f "$output_tmp" ]]; then
    rm -f "$output_tmp"
  fi
}
trap cleanup EXIT

jq -n \
  --arg phase "fault" \
  --arg captured_at "$CAPTURED_AT" \
  --arg timestamp "$OBSERVED_AT" \
  --arg trace_id "$TRACE_ID" \
  --arg result "$OBSERVATION_RESULT" \
  --argjson success "$CURL_SUCCESS" \
  '{
    phase: $phase,
    captured_at: $captured_at,
    points: [
      {
        name: "mac_curl",
        timestamp: $timestamp,
        trace_id: $trace_id,
        result: $result,
        success: $success
      }
    ]
  }' >"$output_tmp"

mv "$output_tmp" "$OUTPUT_PATH"
output_tmp=""

echo "Fault observation recorded: $OUTPUT_PATH"
echo "outcome=$outcome http_status=$HTTP_STATUS curl_exit_code=$curl_exit_code"
