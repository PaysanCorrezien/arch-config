#!/bin/bash
# Auto-add downloaded books to Calibre library.
# Triggered by calibre-autoadd.timer. Idempotent — duplicates merge.
# When at least one new book is actually added, restart Calibre so its
# running processes pick up the change (otherwise the UI keeps a stale view).
set -e

LIB='/config/Calibre Library'
WATCH_PATHS=(
  /data/torrents/books   # qBittorrent (clientCategory=books)
  /data/usenet/books     # SABnzbd (books category)
)

added_new=0

for p in "${WATCH_PATHS[@]}"; do
  if ! docker exec mediastack_calibre test -d "$p"; then continue; fi
  if [ -z "$(docker exec mediastack_calibre find "$p" -mindepth 1 -maxdepth 3 -type f \
        \( -iname '*.epub' -o -iname '*.mobi' -o -iname '*.azw3' -o -iname '*.pdf' -o -iname '*.cbz' -o -iname '*.cbr' \) 2>/dev/null | head -1)" ]; then
    continue
  fi
  out=$(docker exec mediastack_calibre calibredb add \
    --with-library "$LIB" --recurse --automerge=overwrite "$p" 2>&1) || true
  echo "$out" | grep -v '^$' || true
  # "Added book ids: ..." means new entries; "Merged book ids: ..." means dupes
  if echo "$out" | grep -q '^Added book ids:'; then
    added_new=1
  fi
done

if [ "$added_new" -eq 1 ]; then
  echo "new books added; restarting Calibre so GUI/server refresh"
  docker restart mediastack_calibre >/dev/null
fi
