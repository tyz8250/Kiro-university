#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly RESULTS_DIR="$PROJECT_ROOT/results"
readonly BASELINE_JSON="$RESULTS_DIR/baseline.json"
readonly FAULT_JSON="$RESULTS_DIR/fault.json"
readonly REPORT_PATH="$RESULTS_DIR/report.md"

for required_command in jq mktemp date; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Required command not found: $required_command" >&2
    exit 1
  fi
done

if [[ ! -f "$BASELINE_JSON" ]]; then
  echo "Baseline record not found: $BASELINE_JSON" >&2
  exit 1
fi

if [[ ! -f "$FAULT_JSON" ]]; then
  echo "Fault record not found: $FAULT_JSON" >&2
  exit 1
fi

if ! jq -e '.phase == "baseline" and (.points | type == "array")' \
  "$BASELINE_JSON" >/dev/null; then
  echo "Invalid baseline ExperimentRecord: $BASELINE_JSON" >&2
  exit 1
fi

if ! jq -e '.phase == "fault" and (.points | type == "array")' \
  "$FAULT_JSON" >/dev/null; then
  echo "Invalid fault ExperimentRecord: $FAULT_JSON" >&2
  exit 1
fi

success_for() {
  local json_file="$1"
  local point_name="$2"

  jq -r --arg name "$point_name" '
    ([.points[]? | select(.name == $name)] | last) as $point |
    if $point == null then
      "not collected"
    elif ($point | has("success") | not) then
      "not collected"
    else
      ($point.success | tostring)
    end
  ' "$json_file"
}

report_tmp=$(mktemp "$RESULTS_DIR/.report.md.XXXXXX")

cleanup() {
  if [[ -n "${report_tmp:-}" && -f "$report_tmp" ]]; then
    rm -f "$report_tmp"
  fi
}
trap cleanup EXIT

{
  echo "# Experiment 1: Baseline / Fault Comparison"
  echo
  printf 'Generated at: %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo
  echo "| Observation Point | Baseline | Fault |"
  echo "|---|---:|---:|"

  for point_name in mac_curl tcpdump docker_ps host_curl go_server_logs; do
    baseline_success=$(success_for "$BASELINE_JSON" "$point_name")
    fault_success=$(success_for "$FAULT_JSON" "$point_name")
    printf '| %s | %s | %s |\n' \
      "$point_name" "$baseline_success" "$fault_success"
  done
} >"$report_tmp"

mv "$report_tmp" "$REPORT_PATH"
report_tmp=""

echo "Comparison report generated: $REPORT_PATH"
