#!/usr/bin/env bash
# Build a pinned llama.cpp and run llama-server as a CPU inference service on the HP.
# This script never downloads or deletes a model, and never changes disks or mounts.
set -Eeuo pipefail

usage() {
  echo 'Usage: sudo bash hp/llm/install-llama-server.sh plan|install|verify'
}
[[ $# -eq 1 ]] || { usage; exit 2; }
action=$1
[[ $action == plan || $action == install || $action == verify ]] || { usage; exit 2; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

llama_repo=https://github.com/ggml-org/llama.cpp.git
llama_tag=v0.7.0
llama_commit=620d2225cc436ab0b001e3200e590e3b286ef9ab
prefix=/opt/llama.cpp
env_file=/etc/homelab/llama-server.env
key_dir=/etc/homelab/llama-server
models_mount=/srv/models

# Read one KEY=value line from the settings file without executing it.
setting() {
  local file=${2:-$env_file}
  sed -n "s/^$1=\(.*\)$/\1/p" "$file" | tail -n 1 | sed 's/[[:space:]]*$//'
}
bytes() {
  numfmt --from=iec "$1"
}

check_host() {
  source /etc/os-release
  [[ $ID == ubuntu && $VERSION_ID == 26.04 ]] || { echo 'Ubuntu 26.04 is required (the HP runs 26.04.1)' >&2; return 1; }
  mountpoint -q "$models_mount" || { echo "$models_mount is not mounted. Fix the models volume first." >&2; return 1; }
  grep -qw avx /proc/cpuinfo || { echo 'This CPU has no AVX; llama.cpp would be too slow to be useful.' >&2; return 1; }
  local cores nodes
  cores=$(lscpu --parse=core,socket | grep -v '^#' | sort -u | wc -l)
  nodes=$(lscpu --parse=node | grep -v '^#' | sort -u | wc -l)
  echo "CPU: $(lscpu | sed -n 's/^Model name:[[:space:]]*//p'), $cores physical cores, $nodes NUMA node(s)"
  grep -qw avx2 /proc/cpuinfo || echo 'CPU has AVX but not AVX2; the build targets this CPU only.'
  echo "RAM visible to Ubuntu: $(free -g | awk '/^Mem:/ {print $2}') GiB"
  if [[ -f $env_file ]]; then
    local threads numa
    threads=$(setting LLAMA_ARG_THREADS)
    numa=$(setting LLAMA_ARG_NUMA)
    [[ $threads == "$cores" ]] || echo "NOTE: LLAMA_ARG_THREADS=$threads but this host has $cores physical cores."
    if (( nodes > 1 )) && [[ -z $numa ]]; then echo 'NOTE: more than one NUMA node; consider LLAMA_ARG_NUMA=distribute.'; fi
    if (( nodes == 1 )) && [[ -n $numa ]]; then echo 'NOTE: LLAMA_ARG_NUMA is set on a single-node host; it has no benefit.'; fi
  fi
  local port holder
  port=$( [[ -f $env_file ]] && setting LLAMA_ARG_PORT || setting LLAMA_ARG_PORT "$script_dir/llama-server.env.example")
  holder=$(ss -Hltnp "sport = :$port" 2>/dev/null | grep -o 'users:(("[^"]*"' | head -n 1 | cut -d'"' -f2 || true)
  if [[ -n $holder && $holder != llama-server ]]; then
    echo "Port $port is already used by $holder. Choose another LLAMA_ARG_PORT." >&2; return 1
  fi
}

# Exit 0 when the model is present, readable and inside the memory budget; 1 otherwise.
check_model() {
  local file=${1:-$env_file} model max total_kib
  model=$(setting LLAMA_ARG_MODEL "$file")
  max=$(setting HOMELAB_LLAMA_MEMORY_MAX "$file")
  [[ $model == "$models_mount"/*.gguf ]] || { echo "LLAMA_ARG_MODEL must be a .gguf file under $models_mount" >&2; return 1; }
  total_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  if (( $(bytes "$max") > total_kib * 1024 * 90 / 100 )); then
    echo "HOMELAB_LLAMA_MEMORY_MAX=$max is more than 90% of this host's RAM. Lower it." >&2; return 1
  fi
  if [[ ! -f $model ]]; then
    echo "Model not found yet: $model"
    echo 'Download it yourself (see docs/features/LLM.md); this installer never downloads models.'
    return 1
  fi
  local dir parts=("$model") size=0 part
  if [[ $model =~ -00001-of-([0-9]{5})\.gguf$ ]]; then
    dir=${model%-00001-of-*}
    parts=()
    for ((i = 1; i <= 10#${BASH_REMATCH[1]}; i++)); do
      part=$(printf '%s-%05d-of-%s.gguf' "$dir" "$i" "${BASH_REMATCH[1]}")
      [[ -f $part ]] || { echo "Split model part missing: $part" >&2; return 1; }
      parts+=("$part")
    done
  fi
  for part in "${parts[@]}"; do size=$((size + $(stat -c %s "$part"))); done
  echo "Model: $model ($(numfmt --to=iec "$size") in ${#parts[@]} file(s)), memory limit $max"
  if (( size * 110 / 100 > $(bytes "$max") )); then
    echo "The model plus about 10% for context and buffers is larger than HOMELAB_LLAMA_MEMORY_MAX=$max." >&2; return 1
  fi
  if id llama >/dev/null 2>&1; then
    for part in "${parts[@]}"; do
      runuser -u llama -- test -r "$part" || {
        echo "The llama account cannot read $part." >&2
        echo "Grant read access, for example: sudo setfacl -m u:llama:rX \"$(dirname "$part")\" && sudo setfacl -m u:llama:r \"$part\"" >&2
        return 1
      }
    done
  fi
  echo "PASS: model file is present and fits the memory limit"
}

health() {
  local port key
  port=$(setting LLAMA_ARG_PORT)
  bash "$script_dir/llama-health.sh"
  key=$(grep -v '^#' "$key_dir/api-keys" | head -n 1)
  curl --fail --silent --show-error --max-time 10 -H "Authorization: Bearer $key" "http://127.0.0.1:$port/v1/models" \
    | python3 -c 'import json,sys; ids=[m["id"] for m in json.load(sys.stdin)["data"]]; print("PASS: /v1/models lists", ", ".join(ids))'
}

case $action in
  plan)
    check_host
    if [[ -f $env_file ]]; then
      echo "Settings: $env_file (kept as is)"
      check_model || true
    else
      echo "Settings: $env_file would be created from hp/llm/llama-server.env.example"
      check_model "$script_dir/llama-server.env.example" || true
    fi
    if [[ -x $prefix/$llama_tag/bin/llama-server ]]; then
      echo "llama.cpp $llama_tag is already built in $prefix/$llama_tag"
    else
      echo "Would build llama.cpp $llama_tag ($llama_commit) into $prefix/$llama_tag"
    fi
    echo 'Plan complete. Nothing was changed.'
    ;;
  install)
    [[ $EUID -eq 0 ]] || { echo 'Run install with sudo.' >&2; exit 2; }
    check_host
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential cmake git ca-certificates curl libssl-dev python3 acl
    if ! id llama >/dev/null 2>&1; then
      useradd --system --user-group --home-dir /var/lib/llama-server --shell /usr/sbin/nologin llama
    fi
    [[ $(id -u llama) -ne 0 ]] || { echo 'llama must be an unprivileged account' >&2; exit 2; }
    install -d -m 0755 /etc/homelab
    install -d -m 0750 -o root -g llama "$key_dir"
    if [[ ! -f $env_file ]]; then
      install -m 0640 -o root -g llama "$script_dir/llama-server.env.example" "$env_file"
      echo "Created $env_file. Review it before starting the service."
    elif ! diff -q "$script_dir/llama-server.env.example" "$env_file" >/dev/null; then
      echo "Keeping your edited $env_file. Compare it with hp/llm/llama-server.env.example after upgrades."
    fi
    if [[ ! -s $key_dir/api-keys ]]; then
      python3 -c 'import secrets; print(secrets.token_urlsafe(32))' > "$key_dir/api-keys"
    fi
    chown root:llama "$env_file" "$key_dir/api-keys"
    chmod 0640 "$env_file" "$key_dir/api-keys"

    build=$prefix/$llama_tag
    if [[ ! -x $build/bin/llama-server ]]; then
      rm -rf "$build.partial"
      git clone --depth 1 --branch "$llama_tag" "$llama_repo" "$build.partial/src"
      [[ $(git -C "$build.partial/src" rev-parse HEAD) == "$llama_commit" ]] || {
        echo "llama.cpp $llama_tag does not match the pinned commit $llama_commit. Stopping." >&2; exit 1;
      }
      # GGML_NATIVE builds for this CPU (AVX, no AVX2 on the E5-2620). The binary is not portable.
      cmake -S "$build.partial/src" -B "$build.partial/build" -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=ON -DBUILD_SHARED_LIBS=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF
      cmake --build "$build.partial/build" --target llama-server -j "$(nproc)"
      install -D -m 0755 "$build.partial/build/bin/llama-server" "$build.partial/bin/llama-server"
      rm -rf "$build.partial/build"
      mv "$build.partial" "$build"
    fi
    ln -sfn "$build" "$prefix/current"
    "$prefix/current/bin/llama-server" --version

    install -m 0755 "$script_dir/llama-health.sh" /usr/local/sbin/llama-health.sh
    install -m 0644 "$script_dir/llama-server.service" /etc/systemd/system/llama-server.service
    install -m 0644 "$script_dir/llama-server-health.service" /etc/systemd/system/llama-server-health.service
    install -m 0644 "$script_dir/llama-server-health.timer" /etc/systemd/system/llama-server-health.timer
    high=$(setting HOMELAB_LLAMA_MEMORY_HIGH) max=$(setting HOMELAB_LLAMA_MEMORY_MAX)
    bytes "$high" >/dev/null && bytes "$max" >/dev/null
    install -d /etc/systemd/system/llama-server.service.d
    printf '[Service]\nMemoryHigh=%s\nMemoryMax=%s\nMemorySwapMax=0\n' "$high" "$max" \
      > /etc/systemd/system/llama-server.service.d/memory.conf
    systemd-analyze verify /etc/systemd/system/llama-server.service /etc/systemd/system/llama-server-health.timer
    systemctl daemon-reload
    systemctl enable llama-server.service llama-server-health.timer
    systemctl start llama-server-health.timer
    if check_model; then
      systemctl restart llama-server.service
      echo 'Started llama-server. Loading a large model from the array can take several minutes.'
      echo 'Check it with: sudo bash hp/llm/install-llama-server.sh verify'
    else
      systemctl stop llama-server.service 2>/dev/null || true
      echo 'Installed but not started. Put the model in place, then run this install again.'
    fi
    printf '\nAPI key for clients (save privately): sudo cat %s/api-keys\n' "$key_dir"
    ;;
  verify)
    [[ $EUID -eq 0 ]] || { echo 'Run verify with sudo.' >&2; exit 2; }
    check_model
    systemctl is-active --quiet llama-server.service || { echo 'llama-server.service is not running' >&2; journalctl -u llama-server -n 40 --no-pager; exit 1; }
    systemctl is-active --quiet llama-server-health.timer || { echo 'llama-server-health.timer is not active' >&2; exit 1; }
    health
    echo 'PASS: llama-server, health check and API'
    ;;
esac
