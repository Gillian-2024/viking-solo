"""Stage Claude Code sessions for `openviking-server ingest`.

Hard-links session jsonl files modified on/after `since` into ingest-staging/,
skipping excluded sessions (e.g. ones that contain pasted secrets).
Originals are never modified, and hard links cost no extra disk.
"""
import json
import os
from datetime import datetime
from pathlib import Path

CONF = Path.home() / ".openviking" / "sources.json"
DST = Path.home() / ".openviking" / "ingest-staging" / "claude_code"


def main():
    cfg = json.loads(CONF.read_text())["sessions"]
    src = Path(os.path.expanduser(cfg["root"]))
    since = datetime.fromisoformat(cfg["since"]).timestamp()
    exclude = set(cfg.get("exclude_session_ids", []))
    n = skipped = 0
    for f in src.glob("*/*.jsonl"):
        if f.stem in exclude or f.stat().st_mtime < since:
            skipped += 1
            continue
        target = DST / f.parent.name / f.name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            target.unlink()
        os.link(f, target)
        n += 1
    print(f"staged={n} skipped={skipped} -> {DST}")


if __name__ == "__main__":
    main()
