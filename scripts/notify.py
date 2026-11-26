"""Turn health-check issues into notifications.

Usage: python3 notify.py "<issue 1>" "<issue 2>" ...   (no args = all clear)

Channels:
  - macOS notification (always)
  - your own command, if `notify.command` is set in ~/.openviking/sources.json.
    It is called as: <command...> <title> <body>
    Use it to create a task in your work IM / task tool, so the reminder lands
    where you already look every day.

Dedup: an issue is sent once when it first appears; a "已恢复" message is sent
when it clears. State lives in ~/.openviking/state/notified.json.
"""
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

HOME = Path.home() / ".openviking"
CONF = HOME / "sources.json"
STATE = HOME / "state" / "notified.json"
LOG = HOME / "logs" / "notify.log"
TAG = "[viking-solo] "


def log(msg):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a") as f:
        f.write(f"{datetime.now():%F %T} {msg}\n")


def user_command():
    if not CONF.exists():
        return None
    cmd = json.loads(CONF.read_text()).get("notify", {}).get("command")
    return [os.path.expanduser(c) for c in cmd] if cmd else None


def send(title, body):
    cmd = user_command()
    if cmd:
        try:
            p = subprocess.run(cmd + [TAG + title, body], capture_output=True, text=True, timeout=60)
            if p.returncode:
                raise RuntimeError((p.stderr or p.stdout).strip()[-300:])
        except Exception as ex:
            log(f"自定义通知失败「{title}」：{ex}")
    # title/body go in as argv, not spliced into the AppleScript source
    subprocess.run(["osascript", "-e", "on run argv", "-e",
                    "display notification (item 2 of argv) with title (item 1 of argv)", "-e", "end run",
                    TAG + title, body[:200]], capture_output=True, timeout=10)


def main():
    current = set(sys.argv[1:])
    sent = set(json.loads(STATE.read_text())) if STATE.exists() else set()
    for issue in sorted(current - sent):
        send(issue.split("：")[0], issue)
        log(f"sent: {issue}")
    for issue in sorted(sent - current):
        send("已恢复：" + issue.split("：")[0], "之前的问题已不再出现：" + issue)
        log(f"recovered: {issue}")
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(sorted(current), ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
