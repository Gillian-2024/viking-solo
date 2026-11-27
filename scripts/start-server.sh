#!/usr/bin/env bash
# launchd / systemd entry for openviking-server: inject the LLM key from a 600 file,
# so it never lives in ov.conf or the service file.
export LLM_API_KEY="$(cat "$HOME/.openviking/llm.key")"
exec "$HOME/.local/bin/openviking-server"
