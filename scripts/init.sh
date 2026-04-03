#!/bin/bash

set -euo pipefail

WORKSPACE_DIR="/workspace"
BENCH_DIR="${WORKSPACE_DIR}/frappe-bench"
SITE_NAME="dev.localhost"
INIT_MARKER="${BENCH_DIR}/sites/.codespace-init-done"

log() {
    echo "[init] $*"
}

ensure_yarn() {
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
        npm install -g yarn
    else
        log "Neither corepack nor npm is available to install yarn"
        return 1
    fi

    if ! command -v yarn >/dev/null 2>&1; then
        log "yarn installation failed"
        return 1
    fi

    log "yarn installed: $(yarn --version)"
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
    log "Configuring Node.js via nvm"
    # shellcheck disable=SC1091
    source /home/frappe/.nvm/nvm.sh

    if command -v node >/dev/null 2>&1 && node -v | grep -q '^v20\.'; then
        log "Node.js 20 is already active"
    else
        nvm install 20
        nvm alias default 20
        nvm use 20
    fi

    if ! grep -q "nvm use 20" ~/.bashrc; then
        echo "nvm use 20" >> ~/.bashrc
    fi
fi

if ! command -v bench >/dev/null 2>&1; then
    log "bench command not found in PATH"
    exit 1
fi

ensure_yarn

cd "${WORKSPACE_DIR}"

if [[ -d "${BENCH_DIR}" ]] && ! is_bench_ready; then
    log "Found partial bench from an earlier failed run, recreating"
    rm -rf "${BENCH_DIR}"
fi

if ! is_bench_ready; then
    log "Initializing bench (this clones the Frappe framework repository once)"
    run_with_timeout 45m bash -lc "printf 'n\n' | bench init --ignore-exist --skip-redis-config-generation --frappe-branch develop frappe-bench"
fi

cd "${BENCH_DIR}"

wait_for_mariadb

# Use containers instead of localhost
bench set-mariadb-host mariadb
bench set-redis-cache-host redis-cache:6379
bench set-redis-queue-host redis-queue:6379
bench set-redis-socketio-host redis-socketio:6379

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