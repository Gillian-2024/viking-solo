#!/bin/zsh
# Daily refresh of a personal OpenViking store. Run by launchd (viking-solo.sync).
# Local files stay the source of truth; this only re-imports them.
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export NO_PROXY="127.0.0.1,localhost"
export LLM_API_KEY="$(cat "$HOME/.openviking/llm.key")"
REPO="${0:A:h:h}"
CONF="$HOME/.openviking/sources.json"
cfg() { python3 -c "import json,os,sys;c=json.load(open('$CONF'));print(eval(sys.argv[1]))" "$1"; }
echo "=== $(date '+%F %T') sync start"

# 1. Cloud docs via your exporter (see exporters/README.md)
EXPORTER="$REPO/$(cfg 'c["cloud_docs"]["exporter"]')"
if [[ -x "$EXPORTER" ]]; then
  "$EXPORTER" export-docs
  "$EXPORTER" export-tables
  "$EXPORTER" export-refs "$(cfg 'c["cloud_docs"]["reference_depth"]')" $(cfg '" ".join(c["cloud_docs"]["reference_seeds"])')
else
  echo "no exporter at $EXPORTER, skipping cloud docs"
fi

# 2. Re-import (OpenViking diffs against the existing tree under the same --to)
INCLUDE="$(cfg 'c["include"]')"
IGNORE="$(cfg 'c["ignore_dirs"]')"
add() { ov add-resource "$1" --to "$2" --include "$INCLUDE" --ignore-dirs "$IGNORE"; }
[[ -d "$HOME/.openviking/cloud/docs" ]] && add "$HOME/.openviking/cloud/docs" viking://resources/cloud/owned
[[ -d "$HOME/.openviking/cloud/refs" ]] && add "$HOME/.openviking/cloud/refs" viking://resources/cloud/refs
python3 - "$CONF" <<'EOF' | while IFS=$'\t' read -r p to; do add "$p" "$to"; done
import json, os, sys
for d in json.load(open(sys.argv[1]))["local_dirs"]:
    print(os.path.expanduser(d["path"]), d["to"], sep="\t")
EOF

# 3. New Claude Code sessions -> memory extraction (cursor-based, only new turns)
python3 "$REPO/scripts/stage_sessions.py"
openviking-server ingest backfill --harness claude_code --since "$(cfg 'c["sessions"]["since"]')"

# 4. Wait for all import tasks (max 2h), then clear upload zips left by add-resource
for i in $(seq 1 240); do
  busy=$(ov task list 2>&1 | grep -cE "running|pending")
  [[ $busy -eq 0 ]] && break
  sleep 30
done
if [[ $busy -eq 0 ]]; then
  rm -rf "$HOME/.openviking/data/temp/upload/"*
  echo "upload cache cleared"
else
  echo "tasks still running after 2h, upload cache kept"
fi

echo "=== $(date '+%F %T') sync done"
