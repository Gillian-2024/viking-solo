#!/usr/bin/env bash
# Example `notify.command`: create a to-do in your task tool for each alert.
# Called by scripts/notify.py as:  notify_task_example.sh <title> <body>
#
# Replace the body of this script with your own tool. Two patterns that work well:
#   - a CLI you already use for your task app:  <your-cli> task create --summary "$1" --description "$2" --due <in 5 min>
#   - the task app's open API over HTTP (e.g. a "create task" endpoint with an app token)
#
# Tip: if you assign the task to yourself, many apps do not push on creation.
# Set the due time a few minutes ahead and add an at-due reminder, so it pings you.
set -eu
title="$1"
body="$2"
echo "[$(date '+%F %T')] would create task: $title | $body" >> "$HOME/.openviking/logs/notify-example.log"
