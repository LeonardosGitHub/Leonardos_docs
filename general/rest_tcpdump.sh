#!/bin/bash

show_help() {
cat << 'EOF'
rest_tcpdump.sh - REST-triggerable tcpdump wrapper for BIG-IP

DESCRIPTION:
  This script provides a REST-friendly wrapper for tcpdump on BIG-IP, enabling controlled packet captures with automatic timeout, size-based file rotation, queryable run status, manual stop capability, and S3 upload.

REQUIREMENTS:
  tcpdump filter syntax must be base64 encoded

ARGUMENTS:
  1) max_duration=<value>       (default: 5m)
    Max runtime of the tcpdump capture.
    Uses the Linux 'timeout' command, so supports:
      - seconds: 20s
      - minutes: 5m
      - raw seconds: 120
    The capture will automatically stop after this time,
    even if no traffic is seen.

    NOTE:
      File rotation settings (max_file_mb, max_files) limit disk usage
      but do not stop the capture early.

  2) basename=<value>           (default: restcap)
    Prefix used for all generated files:
      - .pcap capture file(s)
      - .log  execution log
      - .pid  process ID
      - .state runtime metadata
      - .latest pointer to most recent run
    Example:
      basename=clientABC
      clientABC-20260317-221044.pcap

  3) max_file_mb=<value>        (default: 500)
    Maximum size of each capture file in MB.
    tcpdump rotates to a new file when the current file reaches this size.

  4) max_files=<value>          (default: 6)
    Maximum number of capture files to keep for a single run.
    Combined with max_file_mb, this limits the total capture size.

    Example:
      max_file_mb=500 and max_files=6 - up to ~3 GB total capture data

  5) query=<yes|no>             (default: no)
    Controls query mode, get current status:
      - query=no  - Do not query
      - query=yes - Query status of the most recent capture for basename

    Query output includes:
      - Process status (running or not running)
      - Process ID (PID)
      - Start time
      - Output files and sizes
      - Capture filter used

  6) stop_tcpdump=<yes|no>      (default: no)
    Controls stop mode; stopping the tcpdump:
      - stop_tcpdump=no  - Do not stop
      - stop_tcpdump=yes - Stop the most recent running capture for basename

    Uses the PID stored in the latest state file and attempts to stop tcpdump gracefully, escalating signals if needed.

  7) filter_b64=<value>         (required when starting a capture)
    Base64-encoded tcpdump filter expression.

    This avoids issues with:
      - spaces
      - parentheses
      - quotes
      - REST/JSON escaping

    Example filter before encoding:
      (host 10.1.1.1 or host 10.1.1.2) and port 443

    Encode with:
      echo -n '(host 10.1.1.1 or host 10.1.1.2) and port 443' | base64 -w 0

    More examples:
      FILTER_B64=$(echo -n 'port 443' | base64 -w 0)
      FILTER_B64=$(echo -n 'host 10.113.206.28 and (port 443 or port 8443)' | base64 -w 0)
      FILTER_B64=$(echo -n '((host 10.113.206.28 or host 10.1.1.10) and (port 443 or port 8443)) and not (src net 192.168.0.0/16 or dst net 172.16.0.0/12)' | base64 -w 0)

    NOTE:
      filter_b64 is ignored when query=yes or stop_tcpdump=yes or upload_s3=yes

  8) upload_s3=<yes|no>        (default: no)
    Controls S3 upload mode:
      - upload_s3=no  - Do not upload
      - upload_s3=yes - Upload the most recent capture for basename to S3

    Behavior:
      - If capture is still running, the script attempts to stop it gracefully, escalating signals if needed
      - Script waits briefly for tcpdump to exit
      - Uploads all associated files:
          *.pcap*, .log, .state
      - Files are uploaded using AWS CLI on the BIG-IP

  9) s3_bucket=<value>         (required when upload_s3=yes)
    Name of the S3 bucket to upload capture files to.

    Upload path format:
      s3://<bucket>/tcpdump/<hostname>/<basename>/<run_id>/

    Example:
      s3://mybucket/tcpdump/ip-10-0-1-144/clientABC/clientABC-20260317-221044/

USAGE:

  Start a capture:
    FILTER_B64=$(echo -n 'port 443' | base64 -w 0)
    /config/cloud/dependencies/rest_tcpdump.sh \
      max_duration=5m \
      basename=clientABC \
      max_file_mb=500 \
      max_files=6 \
      query=no \
      stop_tcpdump=no \
      filter_b64="$FILTER_B64"

  Query the latest run for a basename:
    /config/cloud/dependencies/rest_tcpdump.sh \
      basename=clientABC \
      query=yes

  Stop the latest running capture for a basename:
    /config/cloud/dependencies/rest_tcpdump.sh \
      basename=clientABC \
      stop_tcpdump=yes

  Upload latest capture to S3:
    /config/cloud/dependencies/rest_tcpdump.sh \
      basename=clientABC \
      upload_s3=yes \
      s3_bucket=mybucket
    NOTE:
      upload_s3 operates on the most recent run for the given basename.
      It does not start a new capture.

REST USAGE EXAMPLES:

  Start a capture:
    FILTER_B64=$(echo -n 'port 443' | base64 -w 0)
    curl -sku '<username>:<password>' https://<bigip>:<port>/mgmt/tm/util/bash -X POST \
        -H "Content-Type: application/json" \
        -d '{"command": "run","utilCmdArgs": "-c \"/path/to/rest_tcpdump.sh basename=clientABC max_duration=5m max_file_mb=500 max_files=6 filter_b64='"$FILTER_B64"'\""}'

  Query the latest run for a basename:
    curl -sku '<username>:<password>' https://<bigip>:<port>/mgmt/tm/util/bash -X POST \
        -H "Content-Type: application/json" \
        -d '{"command": "run", "utilCmdArgs": "-c \"/path/to/rest_tcpdump.sh basename=clientABC query=yes\""}'

  Stop the latest running capture for a basename:
    curl -sku '<username>:<password>' https://<bigip>:<port>/mgmt/tm/util/bash -X POST \
        -H "Content-Type: application/json" \
        -d '{"command": "run", "utilCmdArgs": "-c \"/path/to/rest_tcpdump.sh basename=clientABC stop_tcpdump=yes\""}'

  Upload latest capture to S3:
    curl -sku '<username>:<password>' https://<bigip>:<port>/mgmt/tm/util/bash -X POST \
        -H "Content-Type: application/json" \
        -d '{"command": "run", "utilCmdArgs": "-c \"/path/to/rest_tcpdump.sh basename=clientABC upload_s3=yes s3_bucket=mybucket\""}'

EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

set -euo pipefail

# Fixed values
IFACE="0.0:nnn"
OUTDIR="/shared/images"

# Paths
TCPDUMP_BIN="/usr/sbin/tcpdump"
BASE64_BIN="/usr/bin/base64"
DATE_BIN="/bin/date"
LS_BIN="/bin/ls"
PS_BIN="/bin/ps"
KILL_BIN="/bin/kill"
AWS_BIN="/opt/aws/awscli-2.2.29/bin/dist/aws"
HOSTNAME_BIN="/bin/hostname"
SLEEP_BIN="/bin/sleep"

# Defaults
MAX_DURATION="5m"
BASENAME="restcap"
MAX_FILE_MB="500"
MAX_FILES="6"
QUERY="no"
STOP_TCPDUMP="no"
FILTER_B64=""
UPLOAD_S3="no"
S3_BUCKET=""

# Parse key=value args
for arg in "$@"; do
  case $arg in
    max_duration=*) MAX_DURATION="${arg#*=}" ;;
    basename=*) BASENAME="${arg#*=}" ;;
    max_file_mb=*) MAX_FILE_MB="${arg#*=}" ;;
    max_files=*) MAX_FILES="${arg#*=}" ;;
    query=*) QUERY="${arg#*=}" ;;
    stop_tcpdump=*) STOP_TCPDUMP="${arg#*=}" ;;
    upload_s3=*) UPLOAD_S3="${arg#*=}" ;;
    s3_bucket=*) S3_BUCKET="${arg#*=}" ;;
    filter_b64=*) FILTER_B64="${arg#*=}" ;;
    *) echo "Unknown argument: $arg"; exit 2 ;;
  esac
done

# Basic argument validation
if [[ "$QUERY" != "yes" && "$QUERY" != "no" ]]; then
  echo "ERROR: query must be yes or no"
  exit 2
fi

if [[ "$STOP_TCPDUMP" != "yes" && "$STOP_TCPDUMP" != "no" ]]; then
  echo "ERROR: stop_tcpdump must be yes or no"
  exit 2
fi

if [[ "$QUERY" == "yes" && "$STOP_TCPDUMP" == "yes" ]]; then
  echo "ERROR: query=yes and stop_tcpdump=yes cannot be used together"
  exit 2
fi

if [[ "$UPLOAD_S3" != "yes" && "$UPLOAD_S3" != "no" ]]; then
  echo "ERROR: upload_s3 must be yes or no"
  exit 2
fi

if [[ "$UPLOAD_S3" == "yes" && -z "$S3_BUCKET" ]]; then
  echo "ERROR: s3_bucket is required when upload_s3=yes"
  exit 2
fi

if [[ "$UPLOAD_S3" == "yes" && ( "$QUERY" == "yes" || "$STOP_TCPDUMP" == "yes" ) ]]; then
  echo "ERROR: upload_s3 cannot be combined with query or stop_tcpdump"
  exit 2
fi


TS="$($DATE_BIN +%Y%m%d-%H%M%S)"
RUN_ID="${BASENAME}-${TS}"
OUTFILE="${OUTDIR}/${RUN_ID}.pcap"
LOGFILE="${OUTDIR}/${RUN_ID}.log"
PIDFILE="${OUTDIR}/${RUN_ID}.pid"
WATCHDOG_PIDFILE="${OUTDIR}/${RUN_ID}.watchdog.pid"
STATEFILE="${OUTDIR}/${RUN_ID}.state"
LATESTFILE="${OUTDIR}/${BASENAME}.latest"

mkdir -p "$OUTDIR"

log() {
  echo "[$($DATE_BIN -Is)] $*" | tee -a "$LOGFILE"
}

write_state() {
  cat > "$STATEFILE" <<EOF
RUN_ID="$RUN_ID"
BASENAME="$BASENAME"
PID="${PID:-}"
WATCHDOG_PID="${WATCHDOG_PID:-}"
START_TIME="${START_TIME:-}"
END_TIME="${END_TIME:-}"
MAX_DURATION="$MAX_DURATION"
IFACE="$IFACE"
OUTFILE="$OUTFILE"
LOGFILE="$LOGFILE"
PIDFILE="$PIDFILE"
MAX_FILE_MB="$MAX_FILE_MB"
MAX_FILES="$MAX_FILES"
FILTER_RAW="$FILTER_RAW"
EOF
}

stop_pid() {
  local pid="$1"

  "$KILL_BIN" -INT "$pid" 2>/dev/null || true
  "$SLEEP_BIN" 2

  if kill -0 "$pid" 2>/dev/null; then
    "$KILL_BIN" -TERM "$pid" 2>/dev/null || true
    "$SLEEP_BIN" 2
  fi

  if kill -0 "$pid" 2>/dev/null; then
    "$KILL_BIN" -KILL "$pid" 2>/dev/null || true
    "$SLEEP_BIN" 1
  fi

  if kill -0 "$pid" 2>/dev/null; then
    return 1
  fi

  return 0
}

query_status() {
  if [[ ! -f "$LATESTFILE" ]]; then
    echo "No capture found for basename: $BASENAME"
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$LATESTFILE"

  QUERY_TS="$($DATE_BIN -Is)"
  PROCESS_STATE="NOT RUNNING"

  if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
    PROCESS_STATE="RUNNING"
  fi

  if [[ -n "${LOGFILE:-}" && -f "${LOGFILE:-}" ]]; then
    {
      echo "[$QUERY_TS] QUERY invoked for BASENAME=${BASENAME:-unknown}"
      echo "[$QUERY_TS] QUERY result: process ${PROCESS_STATE}"
    } >> "$LOGFILE"
  fi

  echo "Run ID      : ${RUN_ID:-unknown}"
  echo "PID         : ${PID:-unknown}"
  echo "Watchdog PID: ${WATCHDOG_PID:-unknown}"
  echo "Start Time  : ${START_TIME:-unknown}"
  echo "End Time    : ${END_TIME:-}"
  echo "Max Duration: ${MAX_DURATION:-unknown}"
  echo "Filter      : ${FILTER_RAW:-unknown}"
  echo "Output Base : ${OUTFILE:-unknown}"


  if [[ "$PROCESS_STATE" == "RUNNING" ]]; then
    echo "Process     : RUNNING"
    $PS_BIN -p "$PID" -o pid= -o etime= -o args=
  else
    echo "Process     : NOT RUNNING"
  fi

  echo
  echo "Files:"
  for f in "${OUTFILE}"*; do
    [[ -e "$f" && "$f" == *.pcap* ]] && $LS_BIN -lh "$f"
  done

  exit 0
}

stop_capture() {
  if [[ ! -f "$LATESTFILE" ]]; then
    echo "No capture found for basename: $BASENAME"
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$LATESTFILE"

  STOP_TS="$($DATE_BIN -Is)"

  if [[ -z "${PID:-}" ]]; then
    echo "No PID found in latest state for basename: $BASENAME"
    exit 1
  fi

  if kill -0 "$PID" 2>/dev/null; then

    if stop_pid "$PID"; then

      if [[ -n "${WATCHDOG_PID:-}" ]] && kill -0 "$WATCHDOG_PID" 2>/dev/null; then
        "$KILL_BIN" "$WATCHDOG_PID" 2>/dev/null || true
      fi

      if [[ -n "${LOGFILE:-}" && -f "${LOGFILE:-}" ]]; then
        {
          echo "[$STOP_TS] STOP invoked for BASENAME=${BASENAME:-unknown}"
          echo "[$STOP_TS] STOP action: stopped PID ${PID}"
        } >> "$LOGFILE"
      fi

      echo "Capture stopped"
      echo "Run ID      : ${RUN_ID:-unknown}"
      echo "PID         : ${PID}"
      echo "Output Base : ${OUTFILE:-unknown}"

    else
      if [[ -n "${LOGFILE:-}" && -f "${LOGFILE:-}" ]]; then
        {
          echo "[$STOP_TS] STOP invoked for BASENAME=${BASENAME:-unknown}"
          echo "[$STOP_TS] STOP action: failed to stop PID ${PID}"
        } >> "$LOGFILE"
      fi

      echo "ERROR: Failed to stop PID $PID"
      exit 1
    fi

  else
    if [[ -n "${WATCHDOG_PID:-}" ]] && kill -0 "$WATCHDOG_PID" 2>/dev/null; then
      "$KILL_BIN" "$WATCHDOG_PID" 2>/dev/null || true
    fi

    if [[ -n "${LOGFILE:-}" && -f "${LOGFILE:-}" ]]; then
      {
        echo "[$STOP_TS] STOP invoked for BASENAME=${BASENAME:-unknown}"
        echo "[$STOP_TS] STOP action: process already not running (PID ${PID})"
      } >> "$LOGFILE"
    fi

    echo "Capture is not running"
    echo "Run ID      : ${RUN_ID:-unknown}"
    echo "PID         : ${PID}"
    echo "Output Base : ${OUTFILE:-unknown}"
  fi

  exit 0
}

upload_to_s3() {
  if [[ ! -f "$LATESTFILE" ]]; then
    echo "No capture found for basename: $BASENAME"
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$LATESTFILE"

  HOST="$($HOSTNAME_BIN -s)"
  S3_PREFIX="tcpdump/$HOST/$BASENAME/$RUN_ID"

  UPLOAD_TS="$($DATE_BIN -Is)"

  # Stop if running
  if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
    echo "Capture running, stopping PID $PID..."

    if stop_pid "$PID"; then
      if [[ -n "${WATCHDOG_PID:-}" ]] && kill -0 "$WATCHDOG_PID" 2>/dev/null; then
        "$KILL_BIN" "$WATCHDOG_PID" 2>/dev/null || true
      fi
    else
      if [[ -n "${LOGFILE:-}" && -f "${LOGFILE:-}" ]]; then
        {
          echo "[$UPLOAD_TS] S3 upload invoked for BASENAME=${BASENAME:-unknown}"
          echo "[$UPLOAD_TS] S3 upload action: failed to stop PID ${PID}"
        } >> "$LOGFILE"
      fi

      echo "ERROR: Capture did not stop cleanly"
      exit 1
    fi
  else
    if [[ -n "${WATCHDOG_PID:-}" ]] && kill -0 "$WATCHDOG_PID" 2>/dev/null; then
      "$KILL_BIN" "$WATCHDOG_PID" 2>/dev/null || true
    fi
  fi

  echo "Uploading to S3: s3://$S3_BUCKET/$S3_PREFIX/"

  FILES=()

  # pcap files
  for f in "${OUTFILE}"*; do
    [[ -e "$f" && "$f" == *.pcap* ]] && FILES+=("$f")
  done

  # log + state
  [[ -f "$LOGFILE" ]] && FILES+=("$LOGFILE")
  [[ -f "$STATEFILE" ]] && FILES+=("$STATEFILE")

  for f in "${FILES[@]}"; do
    BASENAME_FILE=$(basename "$f")

    echo "Uploading $f..."
    "$AWS_BIN" s3 cp "$f" "s3://$S3_BUCKET/$S3_PREFIX/$BASENAME_FILE" || {
      if [[ -n "${LOGFILE:-}" && -f "${LOGFILE:-}" ]]; then
        {
          echo "[$UPLOAD_TS] S3 upload invoked for BASENAME=${BASENAME:-unknown}"
          echo "[$UPLOAD_TS] S3 upload action: failed uploading $f"
        } >> "$LOGFILE"
      fi

      echo "ERROR uploading $f"
      exit 1
    }
  done

  # log upload event
  if [[ -n "${LOGFILE:-}" && -f "${LOGFILE:-}" ]]; then
    {
      echo "[$UPLOAD_TS] S3 upload completed"
      echo "[$UPLOAD_TS] Bucket: $S3_BUCKET"
      echo "[$UPLOAD_TS] Prefix: $S3_PREFIX"
    } >> "$LOGFILE"
  fi

  echo "Upload complete"
  echo "S3 path: s3://$S3_BUCKET/$S3_PREFIX/"

  exit 0
}

# Handle s3 upload
if [[ "$UPLOAD_S3" == "yes" ]]; then
  upload_to_s3
fi

# Handle stop modes
if [[ "$STOP_TCPDUMP" == "yes" ]]; then
  stop_capture
fi

# Handle query modes
if [[ "$QUERY" == "yes" ]]; then
  query_status
fi

# Enforce base64 filter for start mode
if [[ -z "$FILTER_B64" ]]; then
  echo "ERROR: filter_b64 is required when starting a capture"
  exit 2
fi

# Decode filter
FILTER_RAW="$(printf '%s' "$FILTER_B64" | $BASE64_BIN -d)"

touch "$LOGFILE"

START_TIME="$($DATE_BIN -Is)"
PID=""
WATCHDOG_PID=""
END_TIME=""
write_state
cp "$STATEFILE" "$LATESTFILE"

log "Starting capture"
log "MAX_DURATION=$MAX_DURATION"
log "IFACE=$IFACE"
log "OUTFILE=$OUTFILE"
log "MAX_FILE_MB=$MAX_FILE_MB"
log "MAX_FILES=$MAX_FILES"
log "FILTER_RAW=$FILTER_RAW"

# Async execution - launch real tcpdump directly
echo "[$($DATE_BIN -Is)] Launching tcpdump" >>"$LOGFILE"

"$TCPDUMP_BIN" \
  -nni "$IFACE" -s0 \
  -C "$MAX_FILE_MB" -W "$MAX_FILES" \
  -w "$OUTFILE" \
  $FILTER_RAW >>"$LOGFILE" 2>&1 &

PID=$!
echo "$PID" > "$PIDFILE"

# Watchdog to stop tcpdump after MAX_DURATION
(
  "$SLEEP_BIN" "$MAX_DURATION"

  if kill -0 "$PID" 2>/dev/null; then
    echo "[$($DATE_BIN -Is)] Watchdog initiating stop for PID $PID after MAX_DURATION=$MAX_DURATION" >>"$LOGFILE"

    if stop_pid "$PID"; then
      echo "[$($DATE_BIN -Is)] Watchdog successfully stopped PID $PID" >>"$LOGFILE"
    else
      echo "[$($DATE_BIN -Is)] Watchdog FAILED to stop PID $PID" >>"$LOGFILE"
    fi
  fi

) >>"$LOGFILE" 2>&1 &


WATCHDOG_PID=$!
echo "$WATCHDOG_PID" > "$WATCHDOG_PIDFILE"

write_state
cp "$STATEFILE" "$LATESTFILE"

echo "Started capture"
echo "Run ID       : $RUN_ID"
echo "PID          : $PID"
echo "Watchdog PID : $WATCHDOG_PID"
echo "Log          : $LOGFILE"
echo "Output       : $OUTFILE"
exit 0