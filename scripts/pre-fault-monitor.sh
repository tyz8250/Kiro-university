#!/usr/bin/env bash

set -euo pipefail

readonly SSH_USER="ec2-user"

usage() {
  echo "Usage: $0 EC2_PUBLIC_IP EC2_KEY_PATH" >&2
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

if ! command -v ssh >/dev/null 2>&1; then
  echo "Required command not found: ssh" >&2
  exit 1
fi

readonly SSH_TARGET="$SSH_USER@$EC2_PUBLIC_IP"
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

if ! ssh "${SSH_OPTIONS[@]}" "$SSH_TARGET" 'bash -s' <<'REMOTE_SCRIPT'
set -euo pipefail

readonly PID_FILE="/tmp/monitor.pid"
readonly TCPDUMP_FILE="/tmp/tcpdump.pcap"
readonly HEALTH_LOG="/tmp/health.log"
readonly DOCKER_LOG="/tmp/docker.log"
readonly TCPDUMP_NOHUP_LOG="/tmp/tcpdump-monitor.nohup.log"
readonly HEALTH_NOHUP_LOG="/tmp/health-monitor.nohup.log"
readonly DOCKER_NOHUP_LOG="/tmp/docker-monitor.nohup.log"

for required_command in bash ip awk nohup tcpdump curl docker date ps mktemp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command not found on EC2: $required_command" >&2
    exit 1
  fi
done

if ! sudo -n true; then
  echo "Passwordless sudo is required for tcpdump" >&2
  exit 1
fi

IFACE=$(ip route show default | awk '{print $5; exit}')
readonly IFACE
if [[ ! "$IFACE" =~ ^[[:alnum:]_.:-]+$ ]]; then
  echo "Could not determine a safe network interface: $IFACE" >&2
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
}

if [[ -f "$PID_FILE" ]]; then
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
    stop_monitored_process "$process_name" "$pid"
  done <"$PID_FILE"
fi

sudo -n rm -f \
  "$TCPDUMP_FILE" \
  "$HEALTH_LOG" \
  "$DOCKER_LOG" \
  "$PID_FILE" \
  "$TCPDUMP_NOHUP_LOG" \
  "$HEALTH_NOHUP_LOG" \
  "$DOCKER_NOHUP_LOG"

touch "$HEALTH_LOG" "$DOCKER_LOG"

tcpdump_pid=""
health_pid=""
docker_pid=""
startup_complete=false

cleanup_failed_startup() {
  local exit_code=$?
  trap - EXIT

  if [[ "$startup_complete" != true ]]; then
    if [[ "$docker_pid" =~ ^[1-9][0-9]*$ ]]; then
      stop_monitored_process docker_pid "$docker_pid" || true
    fi
    if [[ "$health_pid" =~ ^[1-9][0-9]*$ ]]; then
      stop_monitored_process health_pid "$health_pid" || true
    fi
    if [[ "$tcpdump_pid" =~ ^[1-9][0-9]*$ ]]; then
      stop_monitored_process tcpdump_pid "$tcpdump_pid" || true
    fi
    sudo -n rm -f "$PID_FILE"
  fi

  exit "$exit_code"
}
trap cleanup_failed_startup EXIT

tcpdump_pid=$(sudo -n bash -c '
  nohup tcpdump -nn -U -i "$1" "tcp port 8080" -w /tmp/tcpdump.pcap \
    </dev/null >/tmp/tcpdump-monitor.nohup.log 2>&1 &
  echo $!
' pre-fault-tcpdump "$IFACE")

health_pid=$(
  nohup bash -c '
    while true; do
      timestamp=$(date -Is)
      if status=$(curl --silent --show-error --output /dev/null \
        --write-out "%{http_code}" --max-time 4 \
        http://localhost:8080/health); then
        :
      else
        status="000"
      fi
      printf "%s %s\n" "$timestamp" "$status" >>/tmp/health.log
      sleep 5
    done
  ' pre-fault-health-monitor \
    </dev/null >/tmp/health-monitor.nohup.log 2>&1 &
  echo $!
)

docker_pid=$(
  nohup bash -c '
    while true; do
      timestamp=$(date -Is)
      if output=$(docker ps --format "{{.Names}} {{.Status}}" 2>&1); then
        if [[ -n "$output" ]]; then
          while IFS= read -r line; do
            printf "%s %s\n" "$timestamp" "$line" >>/tmp/docker.log
          done <<<"$output"
        else
          printf "%s %s\n" "$timestamp" "<no-running-containers>" >>/tmp/docker.log
        fi
      else
        printf "%s ERROR %s\n" "$timestamp" "$output" >>/tmp/docker.log
      fi
      sleep 5
    done
  ' pre-fault-docker-monitor \
    </dev/null >/tmp/docker-monitor.nohup.log 2>&1 &
  echo $!
)

for pid in "$tcpdump_pid" "$health_pid" "$docker_pid"; do
  if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
    echo "Monitor returned an invalid PID: $pid" >&2
    exit 1
  fi
done

sleep 2

for process_name in tcpdump_pid health_pid docker_pid; do
  pid="${!process_name}"
  if ! pid_is_alive "$process_name" "$pid" || ! process_matches "$process_name" "$pid"; then
    echo "$process_name failed to stay running (PID $pid)" >&2
    exit 1
  fi
done

pid_file_tmp=$(mktemp /tmp/monitor.pid.XXXXXX)
printf 'tcpdump_pid=%s\nhealth_pid=%s\ndocker_pid=%s\n' \
  "$tcpdump_pid" "$health_pid" "$docker_pid" >"$pid_file_tmp"
chmod 600 "$pid_file_tmp"
mv "$pid_file_tmp" "$PID_FILE"

startup_complete=true
printf 'Monitoring started on interface %s\n' "$IFACE"
printf 'tcpdump_pid=%s health_pid=%s docker_pid=%s\n' \
  "$tcpdump_pid" "$health_pid" "$docker_pid"
REMOTE_SCRIPT
then
  echo "Failed to start pre-fault monitors on $SSH_TARGET" >&2
  exit 1
fi
