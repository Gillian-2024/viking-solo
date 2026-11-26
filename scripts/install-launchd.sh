#!/bin/zsh
# Install two launchd agents: the OpenViking server (always on) and the daily sync.
# Usage: scripts/install-launchd.sh [HH:MM]   (default 11:30)
set -eu
REPO="${0:A:h:h}"
AGENTS="$HOME/Library/LaunchAgents"
LOGS="$HOME/.openviking/logs"
TIME="${1:-11:30}"
mkdir -p "$AGENTS" "$LOGS"
chmod 700 "$REPO/scripts/start-server.sh" "$REPO/scripts/daily-sync.sh"

cat > "$AGENTS/viking-solo.server.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>viking-solo.server</string>
  <key>ProgramArguments</key><array><string>$REPO/scripts/start-server.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOGS/server.log</string>
  <key>StandardErrorPath</key><string>$LOGS/server.log</string>
</dict></plist>
EOF

cat > "$AGENTS/viking-solo.sync.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>viking-solo.sync</string>
  <key>ProgramArguments</key><array><string>$REPO/scripts/daily-sync.sh</string></array>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>${TIME%%:*}</integer>
    <key>Minute</key><integer>${TIME##*:}</integer>
  </dict>
  <key>StandardOutPath</key><string>$LOGS/sync.log</string>
  <key>StandardErrorPath</key><string>$LOGS/sync.log</string>
</dict></plist>
EOF

for label in viking-solo.server viking-solo.sync; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENTS/$label.plist"
done
echo "installed: viking-solo.server (always on), viking-solo.sync (daily $TIME)"
