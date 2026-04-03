#!/bin/bash

set -euo pipefail

WORKSPACE_DIR="/workspace"
BENCH_DIR="${WORKSPACE_DIR}/frappe-bench"
SITE_NAME="dev.localhost"

if [[ -s "/home/frappe/.nvm/nvm.sh" ]]; then
    echo "[init] Configuring Node.js via nvm"
    # shellcheck disable=SC1091
    source /home/frappe/.nvm/nvm.sh
    nvm install 20
    nvm alias default 20
    nvm use 20

    if ! grep -q "nvm use 20" ~/.bashrc; then
        echo "nvm use 20" >> ~/.bashrc
    fi
fi

if ! command -v bench >/dev/null 2>&1; then
    echo "bench command not found in PATH"
    exit 1
fi

cd "${WORKSPACE_DIR}"

if [[ -d "${BENCH_DIR}" && ! -d "${BENCH_DIR}/apps/frappe" ]]; then
    rm -rf "${BENCH_DIR}"
fi

if [[ ! -d "${BENCH_DIR}/apps/frappe" ]]; then
    echo "[init] Initializing bench (this can take several minutes)"
    bench init --ignore-exist --skip-redis-config-generation frappe-bench
fi

cd "${BENCH_DIR}"

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
    echo "[init] Creating site ${SITE_NAME}"
    bench new-site "${SITE_NAME}" --mariadb-root-password 123 --admin-password admin --no-mariadb-socket
fi

echo "[init] Applying development defaults"
bench --site "${SITE_NAME}" set-config developer_mode 1
bench --site "${SITE_NAME}" clear-cache
bench use "${SITE_NAME}"

echo "[init] Setup complete"