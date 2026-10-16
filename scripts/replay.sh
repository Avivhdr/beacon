#!/usr/bin/env bash
# Forgets the last N hours of activity (default 24) and relaunches the app,
# so the next poll treats it as new and posts banners for anything still unread on GitHub.
set -euo pipefail
HOURS="${1:-24}"
STATE="$HOME/Library/Application Support/Beacon/state.json"
LEGACY="$HOME/Library/Application Support/GitHubNotifications/state.json"

# The new app copies the old state on first launch. Edit the copy it will read.
if [[ ! -f "$STATE" && -f "$LEGACY" ]]; then
  mkdir -p "$(dirname "$STATE")"
  cp "$LEGACY" "$STATE"
fi

pkill -x Beacon || true
python3 - "$STATE" "$HOURS" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
path, hours = sys.argv[1], int(sys.argv[2])
cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
fmt = lambda d: d.strftime("%Y-%m-%dT%H:%M:%SZ")
parse = lambda s: datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
state = json.load(open(path))
before = len(state["items"])
state["items"] = [i for i in state["items"] if parse(i["createdAt"]) < cutoff]
state["lastPoll"] = fmt(cutoff)
state.pop("lastModified", None)
state["checkedAt"] = {k: min(v, fmt(cutoff)) for k, v in state["checkedAt"].items()}
json.dump(state, open(path, "w"))
print(f"Forgot {before - len(state['items'])} items from the last {hours}h")
PY
open "/Applications/Beacon.app"
