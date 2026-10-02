#!/usr/bin/env bash

set -euo pipefail

readonly MAX_WAIT_SECONDS=30
readonly POLL_INTERVAL_SECONDS=2

usage() {
  echo "Usage: $0 EC2_PUBLIC_IP" >&2
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

for required_command in curl date sleep; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command not found: $required_command" >&2
    exit 1
  fi
done

readonly URL="http://$EC2_PUBLIC_IP:8080/health"
start_time=$(date +%s)
deadline=$((start_time + MAX_WAIT_SECONDS))

while true; do
  now=$(date +%s)
  remaining=$((deadline - now))
  if ((remaining <= 0)); then
    break
  fi

  request_timeout=2
  if ((remaining < request_timeout)); then
    request_timeout=$remaining
  fi

  if http_status=$(curl --silent --show-error --output /dev/null \
    --connect-timeout "$request_timeout" \
    --max-time "$request_timeout" \
    --write-out '%{http_code}' \
    "$URL" 2>/dev/null); then
    :
  else
    http_status="000"
  fi

  now=$(date +%s)
  elapsed=$((now - start_time))
  if [[ "$http_status" == "200" && "$elapsed" -le "$MAX_WAIT_SECONDS" ]]; then
    echo "Restore confirmed: HTTP 200 after ${elapsed}s"
    exit 0
  fi

  remaining=$((deadline - now))
  if ((remaining <= 0)); then
    break
  fi

  sleep_for=$POLL_INTERVAL_SECONDS
  if ((remaining < sleep_for)); then
    sleep_for=$remaining
  fi
  sleep "$sleep_for"
done

elapsed=$(($(date +%s) - start_time))
echo "Restore check failed: HTTP 200 was not received within ${MAX_WAIT_SECONDS}s (elapsed ${elapsed}s)" >&2
exit 1
