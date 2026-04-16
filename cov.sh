#!/usr/bin/env bash
set -euo pipefail
# set -x

PID=-1

if [[ "${OSTYPE:-}" == darwin* ]]; then
  NPROC="$(sysctl -n hw.ncpu)"
  LCOV_EXTRA_ARGS=(--gcov-tool gcov-15)
else
  NPROC="$(nproc 2>/dev/null || echo 1)"
  LCOV_EXTRA_ARGS=()
fi

LCOV_EXTRA_ARGS+=(--ignore-errors inconsistent,inconsistent --ignore-errors corrupt,corrupt)

INTERVAL="${INTERVAL:-60}"
TRIGGER_SIGNAL="${TRIGGER_SIGNAL:-USR2}"
OUT_ROOT="${OUTPUT_DIR:-/coverage_data}"
NAME="${NAME:-proftpd}"
LOG="${LOG:-/dev/null}"
LOG_ERR="${LOG_ERR:-/dev/null}"
PORT="${PORT:-2121}"
D_LEVEL="${D_LEVEL:-1}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="${ROOT_DIR}/.cov-runtime"
CONF_FILE="${ROOT_DIR}/cov-proftpd.conf"
STAMP="$(date "+%Y-%m-%d_%H:%M:%S")"
OUT_DIR="${OUT_ROOT}/${NAME}_${STAMP}"
CSV_FILE="${OUT_DIR}/coverage.csv"

mkdir -p "${OUT_DIR}" "${RUNTIME_DIR}" "${ROOT_DIR}/.cov-ftp-root"
chmod -R 777 "${OUT_DIR}" "${RUNTIME_DIR}" "${ROOT_DIR}/.cov-ftp-root"
echo "timestamp,lines_hit,lines_total,functions_hit,functions_total,branches_hit,branches_total" > "${CSV_FILE}"

if [[ ! -f "${CONF_FILE}" ]]; then
  cat > "${CONF_FILE}" <<EOF
ServerName "proftpd-cov"
ServerType standalone
DefaultServer on
UseIPv6 off
Port ${PORT}
Umask 022
MaxInstances 30
User nobody
Group nogroup
RequireValidShell off
# DefaultRoot /home/ubuntu
PidFile ${RUNTIME_DIR}/proftpd.pid
ScoreboardFile off
SystemLog ${LOG}
TransferLog none
TimeoutNoTransfer 30
TimeoutIdle 30
TimeoutStalled 30
DelayEngine off
EOF
fi

summary_to_csv() {
  local ts="${1:-$(date "+%Y-%m-%d_%H:%M:%S")}";
  local summary
  summary="$(lcov --summary merged.info --rc branch_coverage=1 "${LCOV_EXTRA_ARGS[@]}")"
  local lines_info
  local functions_info
  local branches_info

  lines_info="$(echo "${summary}" | grep -E "^  lines" | sed -E 's/.*\(([0-9]+) of ([0-9]+).*/\1,\2/' || echo "-,-")"
  functions_info="$(echo "${summary}" | grep -E "^  functions" | sed -E 's/.*\(([0-9]+) of ([0-9]+).*/\1,\2/' || echo "-,-")"
  branches_info="$(echo "${summary}" | grep -E "^  branches" | grep -q "of" && \
    echo "${summary}" | grep -E "^  branches" | sed -E 's/.*\(([0-9]+) of ([0-9]+).*/\1,\2/' || echo "-,-")"

  echo "${summary}"

  echo "${ts},${lines_info},${functions_info},${branches_info}" >> "${CSV_FILE}"
}

capture_and_merge() {
  lcov --capture --directory . --output-file coverage.info --rc branch_coverage=1 -j "${NPROC}" -q "${LCOV_EXTRA_ARGS[@]}"
  if [[ -f merged.info ]]; then
    lcov --add-tracefile merged.info --add-tracefile coverage.info --output-file merged.info --rc branch_coverage=1 -j "${NPROC}" -q "${LCOV_EXTRA_ARGS[@]}"
  else
    cp coverage.info merged.info
  fi
}

cleanup() {
  capture_and_merge || true
  summary_to_csv "exit" || true
  cp merged.info "${OUT_DIR}/coverage.info" || true
  genhtml merged.info --output-directory "${OUT_DIR}/html_report" --rc branch_coverage=1 -q --ignore-errors inconsistent,inconsistent --ignore-errors corrupt,corrupt  || true
  exit 0
}

trap cleanup INT TERM QUIT
 
chown -R nobody .

(
  trap "kill 0" SIGINT SIGTERM EXIT

  while true; do
    ./proftpd -n -d "${D_LEVEL}" -c "${CONF_FILE}" >"${LOG}" 2>"${LOG_ERR}" &
    pid=$!
    wait $pid
  done
) &

sleep 3

while true; do
  sleep "${INTERVAL}"
  capture_and_merge
  summary_to_csv
done
