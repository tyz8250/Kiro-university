#!/usr/bin/env bash

set -euo pipefail

readonly SSH_USER="ec2-user"
readonly CONTAINER_NAME="go-server"

usage() {
  echo "Usage: $0 EC2_PUBLIC_IP EC2_KEY_PATH" >&2
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
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

for required_command in ssh scp jq tcpdump mktemp grep awk date; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command not found: $required_command" >&2
    exit 1
  fi
done

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly RESULTS_DIR="$PROJECT_ROOT/results"
readonly FAULT_JSON="$RESULTS_DIR/fault.json"
readonly SSH_TARGET="$SSH_USER@$EC2_PUBLIC_IP"
readonly COLLECTED_AT="$(timestamp_utc)"

SSH_OPTIONS=(
  -i "$EC2_KEY_PATH"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

if [[ ! -f "$FAULT_JSON" ]]; then
  echo "Fault record not found; run observe.sh first: $FAULT_JSON" >&2
  exit 1
fi

if ! jq -e '
  .phase == "fault" and
  (.points | type == "array") and
  ([.points[] | select(.name == "mac_curl")] | length > 0)
' "$FAULT_JSON" >/dev/null; then
  echo "Fault record is not a valid partial ExperimentRecord: $FAULT_JSON" >&2
  exit 1
fi

if ! ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" true; then
  echo "Unable to connect to $SSH_TARGET over SSH" >&2
  exit 1
fi

if ! ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" 'bash -s' <<'REMOTE_SCRIPT'
set -euo pipefail

readonly PID_FILE="/tmp/monitor.pid"
readonly TCPDUMP_FILE="/tmp/tcpdump.pcap"
readonly HEALTH_LOG="/tmp/health.log"
readonly DOCKER_LOG="/tmp/docker.log"

if [[ ! -f "$PID_FILE" ]]; then
  echo "PID file not found: $PID_FILE" >&2
  exit 1
fi

if ! sudo -n true; then
  echo "Passwordless sudo is required to stop tcpdump and prepare its pcap" >&2
  exit 1
fi

pid_is_alive() {
  local process_name="$1"
  local pid="$2"

  if [[ "$process_name" == "tcpdump_pid" ]]; then
    sudo -n kill -0 "$pid" 2>/dev/null
  else
    kill -0 "$pid" 2>/dev/null
  fi
}

process_matches() {
  local process_name="$1"
  local pid="$2"
  local args

  if [[ "$process_name" == "tcpdump_pid" ]]; then
    args=$(sudo -n ps -p "$pid" -o args= 2>/dev/null || true)
    [[ "$args" == *"tcpdump"* && "$args" == *"/tmp/tcpdump.pcap"* ]]
  elif [[ "$process_name" == "health_pid" ]]; then
    args=$(ps -p "$pid" -o args= 2>/dev/null || true)
    [[ "$args" == *"pre-fault-health-monitor"* ]]
  elif [[ "$process_name" == "docker_pid" ]]; then
    args=$(ps -p "$pid" -o args= 2>/dev/null || true)
    [[ "$args" == *"pre-fault-docker-monitor"* ]]
  else
    return 1
  fi
}

signal_process() {
  local process_name="$1"
  local signal="$2"
  local pid="$3"

  if [[ "$process_name" == "tcpdump_pid" ]]; then
    sudo -n kill "-$signal" "$pid"
  else
    kill "-$signal" "$pid"
  fi
}

stop_monitored_process() {
  local process_name="$1"
  local pid="$2"

  if ! pid_is_alive "$process_name" "$pid"; then
    return 0
  fi

  if ! process_matches "$process_name" "$pid"; then
    echo "Refusing to stop PID $pid: it does not match $process_name" >&2
    return 1
  fi

  signal_process "$process_name" TERM "$pid"
  for _ in 1 2 3 4 5; do
    if ! pid_is_alive "$process_name" "$pid"; then
      return 0
    fi
    sleep 1
  done

  signal_process "$process_name" KILL "$pid"
  sleep 1
  if pid_is_alive "$process_name" "$pid"; then
    echo "Failed to stop $process_name (PID $pid)" >&2
    return 1
  fi
}

declare -A monitor_pids=()
while IFS='=' read -r process_name pid extra; do
  if [[ -z "$process_name" && -z "$pid" ]]; then
    continue
  fi
  case "$process_name" in
    tcpdump_pid | health_pid | docker_pid) ;;
    *)
      echo "Invalid process name in $PID_FILE: $process_name" >&2
      exit 1
      ;;
  esac
  if [[ -n "${extra:-}" || ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid PID entry in $PID_FILE: $process_name=$pid" >&2
    exit 1
  fi
  monitor_pids["$process_name"]="$pid"
done <"$PID_FILE"

for process_name in tcpdump_pid health_pid docker_pid; do
  if [[ -z "${monitor_pids[$process_name]:-}" ]]; then
    echo "Missing $process_name in $PID_FILE" >&2
    exit 1
  fi
done

# tcpdumpを先に停止してpcapのバッファを確実に書き出す。
stop_monitored_process tcpdump_pid "${monitor_pids[tcpdump_pid]}"
stop_monitored_process health_pid "${monitor_pids[health_pid]}"
stop_monitored_process docker_pid "${monitor_pids[docker_pid]}"

for artifact in "$TCPDUMP_FILE" "$HEALTH_LOG" "$DOCKER_LOG"; do
  if [[ ! -f "$artifact" ]]; then
    echo "Expected monitor artifact not found: $artifact" >&2
    exit 1
  fi
done

# tcpdumpのroot所有ファイルを、削除せずec2-userがscpできる状態にする。
sudo -n chown ec2-user:ec2-user "$TCPDUMP_FILE"
sudo -n chmod 600 "$TCPDUMP_FILE"

if [[ ! -r "$TCPDUMP_FILE" || ! -r "$HEALTH_LOG" || ! -r "$DOCKER_LOG" ]]; then
  echo "One or more monitor artifacts are not readable by ec2-user" >&2
  exit 1
fi
REMOTE_SCRIPT
then
  echo "Failed to stop monitors or prepare artifacts on $SSH_TARGET" >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"
staging_dir=$(mktemp -d "$RESULTS_DIR/.post-restore.XXXXXX")
json_tmp=""

cleanup() {
  if [[ -n "${json_tmp:-}" && -f "$json_tmp" ]]; then
    rm -f "$json_tmp"
  fi
  if [[ -n "${staging_dir:-}" && -d "$staging_dir" ]]; then
    rm -rf -- "$staging_dir"
  fi
}
trap cleanup EXIT

scp "${SSH_OPTIONS[@]}" "$SSH_TARGET:/tmp/tcpdump.pcap" "$staging_dir/tcpdump.pcap"
scp "${SSH_OPTIONS[@]}" "$SSH_TARGET:/tmp/health.log" "$staging_dir/health.log"
scp "${SSH_OPTIONS[@]}" "$SSH_TARGET:/tmp/docker.log" "$staging_dir/docker.log"

if ! TCPDUMP_OUTPUT=$(tcpdump -nn -tttt -r "$staging_dir/tcpdump.pcap" 'tcp port 8080' 2>&1); then
  echo "Unable to read collected tcpdump.pcap" >&2
  exit 1
fi

TCPDUMP_SUCCESS=false
if grep -Eq '\.8080([:[:space:]]|$)' <<<"$TCPDUMP_OUTPUT"; then
  TCPDUMP_SUCCESS=true
fi

HEALTH_OUTPUT=$(<"$staging_dir/health.log")
HEALTH_SUCCESS=false
if awk '
  NF >= 2 { seen = 1; if ($NF != "200") bad = 1 }
  END { exit !(seen && !bad) }
' "$staging_dir/health.log"; then
  HEALTH_SUCCESS=true
fi

DOCKER_OUTPUT=$(<"$staging_dir/docker.log")
DOCKER_SUCCESS=false
if grep -Eq "[[:space:]]${CONTAINER_NAME}[[:space:]]+Up([[:space:]]|$)" \
  "$staging_dir/docker.log"; then
  DOCKER_SUCCESS=true
fi

printf -v TCPDUMP_RESULT \
  'artifact=results/fault-tcpdump.pcap\nport_8080_packet_observed=%s\n%s' \
  "$TCPDUMP_SUCCESS" "$TCPDUMP_OUTPUT"
printf -v HEALTH_RESULT \
  'artifact=results/fault-health.log\nall_samples_http_200=%s\n%s' \
  "$HEALTH_SUCCESS" "$HEALTH_OUTPUT"
printf -v DOCKER_RESULT \
  'artifact=results/fault-docker.log\ngo_server_seen_running=%s\n%s' \
  "$DOCKER_SUCCESS" "$DOCKER_OUTPUT"

json_tmp=$(mktemp "$RESULTS_DIR/.fault.json.XXXXXX")
jq \
  --arg timestamp "$COLLECTED_AT" \
  --arg tcpdump_result "$TCPDUMP_RESULT" \
  --argjson tcpdump_success "$TCPDUMP_SUCCESS" \
  --arg health_result "$HEALTH_RESULT" \
  --argjson health_success "$HEALTH_SUCCESS" \
  --arg docker_result "$DOCKER_RESULT" \
  --argjson docker_success "$DOCKER_SUCCESS" \
  '
    .points = (
      [.points[] | select(
        .name != "tcpdump" and
        .name != "host_curl" and
        .name != "docker_ps"
      )] + [
        {
          name: "tcpdump",
          timestamp: $timestamp,
          trace_id: "",
          result: $tcpdump_result,
          success: $tcpdump_success
        },
        {
          name: "docker_ps",
          timestamp: $timestamp,
          trace_id: "",
          result: $docker_result,
          success: $docker_success
        },
        {
          name: "host_curl",
          timestamp: $timestamp,
          trace_id: "",
          result: $health_result,
          success: $health_success
        }
      ]
    )
  ' "$FAULT_JSON" >"$json_tmp"

mv "$staging_dir/tcpdump.pcap" "$RESULTS_DIR/fault-tcpdump.pcap"
mv "$staging_dir/health.log" "$RESULTS_DIR/fault-health.log"
mv "$staging_dir/docker.log" "$RESULTS_DIR/fault-docker.log"
mv "$json_tmp" "$FAULT_JSON"
json_tmp=""

echo "Post-restore artifacts collected and merged into: $FAULT_JSON"
