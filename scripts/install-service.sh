#!/usr/bin/env bash
# Install two user services: the OpenViking server (always on) and the daily sync.
#   macOS -> launchd agents in ~/Library/LaunchAgents
#   Linux -> systemd --user units in ~/.config/systemd/user (also works in WSL2 with systemd on)
# Usage: scripts/install-service.sh [HH:MM]   (default 11:30)
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOGS="$HOME/.openviking/logs"
TIME="${1:-11:30}"
HOUR="${TIME%%:*}"; MIN="${TIME##*:}"
mkdir -p "$LOGS"
chmod 700 "$REPO/scripts/start-server.sh" "$REPO/scripts/daily-sync.sh"

install_launchd() {
  local agents="$HOME/Library/LaunchAgents"
  mkdir -p "$agents"
  cat > "$agents/viking-solo.server.plist" <<EOF
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
  cat > "$agents/viking-solo.sync.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>viking-solo.sync</string>
  <key>ProgramArguments</key><array><string>$REPO/scripts/daily-sync.sh</string></array>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>$((10#$HOUR))</integer>
    <key>Minute</key><integer>$((10#$MIN))</integer>
  </dict>
  <key>StandardOutPath</key><string>$LOGS/sync.log</string>
  <key>StandardErrorPath</key><string>$LOGS/sync.log</string>
</dict></plist>
EOF
  for label in viking-solo.server viking-solo.sync; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$agents/$label.plist"
  done
}

install_systemd() {
  command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1 || {
    echo "systemd --user is not available. On WSL2 add '[boot] systemd=true' to /etc/wsl.conf and run 'wsl --shutdown';" >&2
    echo "otherwise run scripts/start-server.sh yourself and schedule scripts/daily-sync.sh with cron." >&2
    exit 1
  }
  local units="$HOME/.config/systemd/user"
  mkdir -p "$units"
  cat > "$units/viking-solo-server.service" <<EOF
[Unit]
Description=viking-solo: OpenViking server

[Service]
ExecStart=$REPO/scripts/start-server.sh
Restart=always
RestartSec=5
StandardOutput=append:$LOGS/server.log
StandardError=append:$LOGS/server.log

[Install]
WantedBy=default.target
EOF
  cat > "$units/viking-solo-sync.service" <<EOF
[Unit]
Description=viking-solo: daily sync

[Service]
Type=oneshot
ExecStart=$REPO/scripts/daily-sync.sh
StandardOutput=append:$LOGS/sync.log
StandardError=append:$LOGS/sync.log
EOF
  cat > "$units/viking-solo-sync.timer" <<EOF
[Unit]
Description=viking-solo: daily sync at $TIME

[Timer]
OnCalendar=*-*-* $HOUR:$MIN:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now viking-solo-server.service viking-solo-sync.timer
  # keep user services running after logout (no-op if already set; may need sudo on some distros)
  loginctl enable-linger "$USER" 2>/dev/null || echo "note: run 'sudo loginctl enable-linger $USER' to keep services up after logout"
}

case "$(uname -s)" in
  Darwin) install_launchd ;;
  Linux)  install_systemd ;;
  *) echo "unsupported OS: $(uname -s). On Windows use WSL2 (see README)." >&2; exit 1 ;;
esac
echo "installed: server (always on), sync (daily $TIME)"
