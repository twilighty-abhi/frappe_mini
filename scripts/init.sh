#!/bin/bash

set -euo pipefail

WORKSPACE_DIR="/workspace"
BENCH_DIR="${WORKSPACE_DIR}/frappe-bench"
SITE_NAME="dev.localhost"
NODE_MAJOR="24"
INIT_MARKER="${BENCH_DIR}/sites/.codespace-init-done"

# Codespaces bind mounts usually do not support hardlinks reliably.
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

log() {
    echo "[init] $*"
}

ensure_yarn() {
    export PATH="$HOME/.local/bin:$PATH"

    if command -v yarn >/dev/null 2>&1; then
        log "yarn already available: $(yarn --version)"
        return 0
    fi

    if command -v corepack >/dev/null 2>&1; then
        log "Installing yarn via corepack"
        corepack enable
        corepack prepare yarn@1.22.22 --activate
    elif command -v npm >/dev/null 2>&1; then
        log "Installing yarn via npm"
        npm install -g yarn@1.22.22
    else
        log "Neither corepack nor npm is available to install yarn"
        return 1
    fi

    # Some environments expose only corepack; provide a stable yarn shim.
    if ! command -v yarn >/dev/null 2>&1 && command -v corepack >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        cat > "$HOME/.local/bin/yarn" <<'EOF'
#!/usr/bin/env bash
exec corepack yarn "$@"
EOF
        chmod +x "$HOME/.local/bin/yarn"
    fi

    hash -r

    if ! command -v yarn >/dev/null 2>&1; then
        log "yarn installation failed"
        return 1
    fi

    log "yarn installed: $(yarn --version) ($(command -v yarn))"
}

run_with_timeout() {
    local duration="$1"
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "${duration}" "$@"
    else
        "$@"
    fi
}

run_bench_init() {
    if command -v timeout >/dev/null 2>&1; then
        printf 'n\n' | timeout 45m bench init --ignore-exist --skip-redis-config-generation --frappe-branch develop frappe-bench
    else
        printf 'n\n' | bench init --ignore-exist --skip-redis-config-generation --frappe-branch develop frappe-bench
    fi
}

wait_for_mariadb() {
    local retries=90
    local attempt=1

    log "Waiting for MariaDB at mariadb:3306"
    while [[ ${attempt} -le ${retries} ]]; do
        if (echo > /dev/tcp/mariadb/3306) >/dev/null 2>&1; then
            log "MariaDB is reachable"
            return 0
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    log "MariaDB did not become reachable in time"
    return 1
}

require_node_major() {
    if ! command -v node >/dev/null 2>&1; then
        log "node is not available in PATH"
        return 1
    fi

    local actual_major
    actual_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ "${actual_major}" != "${NODE_MAJOR}" ]]; then
        log "Expected Node ${NODE_MAJOR}.x, but got $(node -v)"
        return 1
    fi

    log "Active node: $(node -v)"
    return 0
}

is_bench_ready() {
    [[ -d "${BENCH_DIR}/apps/frappe" ]] &&
    [[ -f "${BENCH_DIR}/sites/common_site_config.json" ]] &&
    [[ -x "${BENCH_DIR}/env/bin/python" ]]
}

if [[ -f "${INIT_MARKER}" ]]; then
    log "Setup already completed earlier, skipping"
    exit 0
fi

if [[ -s "/home/frappe/.nvm/nvm.sh" ]]; then
    log "Configuring Node.js via nvm (target major: ${NODE_MAJOR})"
    # shellcheck disable=SC1091
    source /home/frappe/.nvm/nvm.sh

    if command -v node >/dev/null 2>&1 && node -v | grep -Eq "^v${NODE_MAJOR}(\\.|$)"; then
        log "Node.js ${NODE_MAJOR} is already active"
    else
        nvm install "${NODE_MAJOR}"
        nvm alias default "${NODE_MAJOR}"
        nvm use "${NODE_MAJOR}"
    fi

    sed -i '/nvm use 20/d' ~/.bashrc
    if ! grep -q "nvm use ${NODE_MAJOR}" ~/.bashrc; then
        echo "nvm use ${NODE_MAJOR}" >> ~/.bashrc
    fi
fi

require_node_major

if ! command -v bench >/dev/null 2>&1; then
    log "bench command not found in PATH"
    exit 1
fi

ensure_yarn
log "Using yarn at: $(command -v yarn)"

cd "${WORKSPACE_DIR}"

if [[ -d "${BENCH_DIR}" ]] && ! is_bench_ready; then
    log "Found partial bench from an earlier failed run, recreating"
    rm -rf "${BENCH_DIR}"
fi

if ! is_bench_ready; then
    log "Initializing bench (this clones the Frappe framework repository once)"
    run_bench_init
fi

cd "${BENCH_DIR}"

wait_for_mariadb

# Use containers instead of localhost
bench set-mariadb-host mariadb
bench set-config -g redis_cache "redis://redis-cache:6379"
bench set-config -g redis_queue "redis://redis-queue:6379"
bench set-config -g redis_socketio "redis://redis-socketio:6379"

# Remove redis processes from Procfile because Redis runs in separate containers.
if [[ -f "./Procfile" ]]; then
    sed -i '/redis/d' ./Procfile
fi

if [[ ! -d "sites/${SITE_NAME}" ]]; then
    log "Creating site ${SITE_NAME}"
    run_with_timeout 20m bench new-site "${SITE_NAME}" --mariadb-root-password 123 --admin-password admin --no-mariadb-socket
fi

log "Applying development defaults"
bench --site "${SITE_NAME}" set-config developer_mode 1
bench --site "${SITE_NAME}" clear-cache
bench use "${SITE_NAME}"

touch "${INIT_MARKER}"

log "Setup complete"