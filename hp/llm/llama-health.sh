#!/usr/bin/env bash
# Check llama-server's /health. Exit 0 ready, 1 loading, 2 down.
# --watchdog restarts the service when it has been up for 15 minutes and still
# is not ready, so a long first load from the RAID array is never interrupted.
set -Eeuo pipefail
env_file=${LLAMA_ENV_FILE:-/etc/homelab/llama-server.env}
mode=${1:-check}
[[ $mode == check || $mode == --watchdog ]] || { echo 'Usage: llama-health.sh [--watchdog]'; exit 64; }

port=$(sed -n 's/^LLAMA_ARG_PORT=\([0-9]\{1,5\}\)[[:space:]]*$/\1/p' "$env_file" | tail -n 1)
port=${port:-8080}
code=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 5 "http://127.0.0.1:$port/health" || true)
case $code in
  200) state=0; echo "PASS: llama-server is ready on port $port" ;;
  503) state=1; echo "llama-server on port $port is still loading the model" ;;
  *)   state=2; echo "llama-server is not answering on port $port (HTTP ${code:-none})" ;;
esac

if [[ $mode == --watchdog && $state -ne 0 ]] && systemctl is-active --quiet llama-server.service; then
  since=$(systemctl show --property=ActiveEnterTimestampMonotonic --value llama-server.service)
  now=$(awk '{printf "%d", $1 * 1000000}' /proc/uptime)
  if (( since > 0 && now - since > 900000000 )); then
    echo 'llama-server has not been ready for 15 minutes; restarting it.'
    systemctl restart llama-server.service
  fi
fi
exit "$state"
