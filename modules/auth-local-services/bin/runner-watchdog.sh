#!/bin/bash
# Kill GitHub Actions Runner.Worker process trees older than MAX_AGE seconds.
# Backstop for job timeouts when a runner worker is starved.
MAX_AGE=${MAX_AGE:-10800}   # 3h, matching the live VPS setting
logger -t runner-watchdog "scan start (max_age=${MAX_AGE}s)"
while read -r pid etimes; do
  [ -z "$pid" ] && continue
  [ "$etimes" -le "$MAX_AGE" ] && continue
  cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-120)
  logger -t runner-watchdog "KILLING pid=$pid age=${etimes}s cmd=$cmd"
  # Signal the worker and its direct children; this is the existing VPS backstop.
  pkill -TERM -P "$pid" 2>/dev/null
  kill -TERM "$pid" 2>/dev/null
  sleep 60
  if kill -0 "$pid" 2>/dev/null; then
    logger -t runner-watchdog "SIGTERM ignored, SIGKILL pid=$pid"
    pkill -KILL -P "$pid" 2>/dev/null
    kill -KILL "$pid" 2>/dev/null
  fi
done < <(ps -eo pid=,etimes=,comm= | awk '$3=="Runner.Worker"{print $1, $2}')
