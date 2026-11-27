#!/usr/bin/env bash
# Daily refresh of a personal OpenViking store. Run by launchd / systemd timer (viking-solo sync).
# Local files stay the source of truth; this only re-imports them.
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export NO_PROXY="127.0.0.1,localhost"
export LLM_API_KEY="$(cat "$HOME/.openviking/llm.key")"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
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

# 5. Health check: anything that needs you goes to attention.md + notify.py
ATT="$HOME/.openviking/logs/attention.md"
issues=()
if [[ "$(uname -s)" == Darwin ]]; then
  restart_server="launchctl kickstart -k gui/\$(id -u)/viking-solo.server"
  restart_ollama="brew services restart ollama"
else
  restart_server="systemctl --user restart viking-solo-server"
  restart_ollama="systemctl restart ollama（或重新运行 ollama serve）"
fi
curl -fsS -m 5 http://127.0.0.1:1933/health >/dev/null || issues+=("OpenViking 服务不通：$restart_server")
curl -fsS -m 5 http://127.0.0.1:11434/api/version >/dev/null || issues+=("Ollama 不通：$restart_ollama")
if [[ -x "$EXPORTER" ]] && ! "$EXPORTER" check >/dev/null 2>&1; then
  issues+=("云文档导出器检查失败（多半是登录过期）：重新登录你的云文档工具")
fi
failed=$(ov task list 2>&1 | grep -c failed)
[[ $failed -gt 0 ]] && issues+=("有 $failed 个导入任务失败：ov task list --status failed 看原因")
[[ -d "$HOME/.openviking/data/viking/default/user/default/memories/preferences" ]] && \
  issues+=("偏好记忆又出现了：检查 ov.conf 的 memory_policy 是否生效")
size=$(du -sm "$HOME/.openviking/data" | cut -f1)
[[ $size -gt 5000 ]] && issues+=("知识库数据已 ${size}MB，超过 5GB：检查 data/temp 等可清理目录")
if (( ${#issues[@]} )); then
  { echo "# viking-solo 待处理（$(date '+%F %T')）"; for i in "${issues[@]}"; do echo "- $i"; done; } > "$ATT"
else
  rm -f "$ATT"
fi
python3 "$REPO/scripts/notify.py" ${issues[@]+"${issues[@]}"}

echo "=== $(date '+%F %T') sync done"
