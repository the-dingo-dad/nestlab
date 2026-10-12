#!/usr/bin/env bash
# Bring nestlab stacks up.
#   ./up-all.sh            -> every stack, in dependency order
#   ./up-all.sh arr media  -> just those stacks
set -euo pipefail

cd "$(dirname "$0")"

# Infra first (proxy, broker, db), then the things that lean on them.
# Any stack folder not listed here gets brought up at the end.
ORDER=(proxy mqtt sql ha downloaders arr media)

if [ $# -gt 0 ]; then
  stacks=("$@")
else
  stacks=("${ORDER[@]}")
  for d in */; do
    d="${d%/}"
    [[ " ${ORDER[*]} " == *" $d "* ]] || stacks+=("$d")
  done
fi

[ -f .env ] || { echo "No stacks/.env - copy .env.template and fill it in first."; exit 1; }

for s in "${stacks[@]}"; do
  if [ ! -f "$s/docker-compose.yaml" ]; then
    echo "-- skipping $s (no docker-compose.yaml)"
    continue
  fi
  echo "== up: $s"
  (cd "$s" && docker compose up -d --remove-orphans)
done

echo "Done."
