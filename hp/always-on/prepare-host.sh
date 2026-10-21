#!/usr/bin/env bash
# Prepare the HP for the always-on Compose stack in this folder.
# It creates data folders and copies example config only when missing.
# It never creates arrays, partitions, filesystems or logical volumes.
set -Eeuo pipefail

usage() { echo 'Usage: sudo bash hp/always-on/prepare-host.sh plan|install'; }
[[ $# -eq 1 && ( $1 == plan || $1 == install ) ]] || { usage; exit 2; }
action=$1
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
env_file=$here/.env

if [[ ! -f $env_file ]]; then
  if [[ $action == install ]]; then
    install -m 600 "$here/.env.example" "$env_file"
    echo "Created $env_file from .env.example. Edit it, then run install again."
    exit 1
  fi
  env_file=$here/.env.example
  echo "No .env yet; planning with .env.example values."
fi
# Read only the settings this script needs, without executing the file:
# .env holds camera passwords and follows Compose's dotenv syntax, not Bash's.
env_value() {
  local line value
  line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?$1[[:space:]]*=" "$env_file" | tail -n 1) || true
  value=${line#*=}
  value=${value#"${value%%[![:space:]]*}"}
  case $value in
    \'*) value=${value:1}; value=${value%%\'*} ;;
    \"*) value=${value:1}; value=${value%%\"*} ;;
    *) value=${value%%[[:space:]]#*}; value=${value%"${value##*[![:space:]]}"} ;;
  esac
  [[ $value != *\$\{* ]] || { echo "$1 uses \${...} interpolation; write the literal path in $env_file" >&2; exit 1; }
  printf '%s' "$value"
}
for var in SERVICES_DATA_ROOT AI_WORKSPACE_DIR FRIGATE_MEDIA_DIR HP_LAN_IP RELAY_UID RELAY_GID FRIGATE_MEMORY; do
  value=$(env_value "$var") || exit 1
  printf -v "$var" '%s' "$value"
done
for var in RELAY_UID RELAY_GID; do
  [[ -z ${!var} || ${!var} =~ ^[0-9]+$ ]] || { echo "$var must be a number in $env_file" >&2; exit 1; }
done

[[ $(stat -c %a "$env_file") == 600 || $env_file == "$here/.env.example" ]] ||
  echo "WARN: $env_file should be mode 600 (chmod 600 $env_file)."

for var in SERVICES_DATA_ROOT AI_WORKSPACE_DIR FRIGATE_MEDIA_DIR HP_LAN_IP; do
  [[ -n ${!var:-} ]] || { echo "$var is empty in $env_file" >&2; exit 1; }
done
case $SERVICES_DATA_ROOT in /srv/*) ;; *) echo "SERVICES_DATA_ROOT must be under /srv" >&2; exit 1 ;; esac

command -v docker >/dev/null && docker compose version >/dev/null 2>&1 ||
  echo "WARN: Docker Engine with the compose plugin is not installed (see docs/ALWAYS-ON.md step 1)."
ip -o -4 address show 2>/dev/null | grep -q " $HP_LAN_IP/" ||
  echo "WARN: HP_LAN_IP $HP_LAN_IP is not assigned to any interface on this host."
[[ -f $AI_WORKSPACE_DIR/TelegramBot/app.py ]] ||
  echo "WARN: $AI_WORKSPACE_DIR/TelegramBot/app.py not found; clone Noxy-HNR/ai-workspace there."

parent=$SERVICES_DATA_ROOT
until [[ -d $parent ]]; do parent=$(dirname "$parent"); done
echo "Data root $SERVICES_DATA_ROOT is on $(df -h --output=target,avail "$parent" | tail -1 | awk '{print $1" ("$2" free)"}')."
echo "Memory: $(free -g | awk '/^Mem:/ {print $2" GiB total, "$7" GiB available"}'). Stack limits: 0.5 GiB relay, ${FRIGATE_MEMORY:-4g} Frigate."

dirs=("$SERVICES_DATA_ROOT/relay-station" "$SERVICES_DATA_ROOT/frigate/config" "$FRIGATE_MEDIA_DIR")
if [[ $action == plan ]]; then
  printf 'Would create (if missing): %s\n' "${dirs[@]}" "$SERVICES_DATA_ROOT/backups (root only)"
  echo "Would copy frigate/config.example.yml to $SERVICES_DATA_ROOT/frigate/config/config.yml if missing."
  exit 0
fi

[[ $EUID -eq 0 ]] || { echo 'Run install with sudo.' >&2; exit 1; }
install -d -m 755 "$SERVICES_DATA_ROOT" "$SERVICES_DATA_ROOT/frigate" "${dirs[@]:1}"
install -d -m 700 "$SERVICES_DATA_ROOT/backups"
install -d -m 700 -o "${RELAY_UID:-10001}" -g "${RELAY_GID:-10001}" "${dirs[0]}"
chown -R "${RELAY_UID:-10001}:${RELAY_GID:-10001}" "${dirs[0]}"
config=$SERVICES_DATA_ROOT/frigate/config/config.yml
[[ -e $config ]] || install -m 644 "$here/frigate/config.example.yml" "$config"
echo "PASS: data folders ready under $SERVICES_DATA_ROOT and $FRIGATE_MEDIA_DIR."
