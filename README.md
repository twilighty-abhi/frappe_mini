# Frappe Codespaces Starter

This repository brings up a Frappe development environment in GitHub Codespaces using Docker Compose.

## What Happens Automatically

When the Codespace starts, `scripts/init.sh` runs from both `postCreateCommand` and `postStartCommand`.

On a fresh setup, it will:

1. Ensure Node.js 24 and Yarn are available.
2. Initialize a bench at `/workspace/frappe-bench` from Frappe `develop`.
3. Configure external services:
   - MariaDB at `mariadb`
   - Redis cache at `redis://redis-cache:6379`
   - Redis queue at `redis://redis-queue:6379`
   - Redis socketio at `redis://redis-socketio:6379`
4. Create site `dev.localhost`.
5. Enable developer mode and set default site.

Defaults used by init:

- Site: `dev.localhost`
- Admin password: `admin`
- DB root user: `root`
- DB root password: `123`

## First-Time Setup

1. Create a Codespace from the latest commit on your branch.
2. Open creation logs:
   - Command Palette -> `Codespaces: View Creation Log`
3. Wait for init to complete.

Expected completion line:

```text
[init] Setup complete
```

## Manual Run

If you want to run setup manually inside Codespace:

```bash
cd /workspace
bash /workspace/scripts/init.sh
```

Verify:

```bash
cd /workspace/frappe-bench
bench --site dev.localhost list-apps
```

## If Codespace Uses Old Commits

Run this in Codespace terminal:

```bash
cd /workspace
git fetch --all --prune
git pull --ff-only
git rev-parse HEAD
```

If still stale, create a brand-new Codespace from the correct branch/commit.

## Recover From Failed/Partial Setup

If setup failed in the middle:

```bash
cd /workspace
rm -rf /workspace/frappe-bench
bash /workspace/scripts/init.sh
```

If terminal is stuck in an interactive process, open a new terminal and run:

```bash
pkill -f "bench new-site" || true
pkill -f "bench_helper.py" || true
pkill -f "mysql" || true
```

Then rerun init.

## Daily Dev Commands

Start services:

```bash
cd /workspace/frappe-bench
bench start
```

Build assets:

```bash
cd /workspace/frappe-bench
bench build
```

Run migrations:

```bash
cd /workspace/frappe-bench
bench --site dev.localhost migrate
```

## Notes

- First run is slow because `bench init` clones Frappe and builds assets.
- Frappe `develop` currently expects Node.js 24.
- `scripts/init.sh` is idempotent and skips once completion marker exists.