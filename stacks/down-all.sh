#!/usr/bin/env bash
# Take nestlab stacks down.
#   ./down-all.sh            -> every stack, reverse dependency order
#   ./down-all.sh arr media  -> just those stacks
# Containers are removed; appdata and the external nestlab-* networks are left alone.
set -euo pipefail

cd "$(dirname "$0")"

# Same order as up-all.sh, walked backwards (unlisted stacks go down first).
ORDER=(proxy mqtt sql ha downloaders arr media)

if [ $# -gt 0 ]; then
  stacks=("$@")
else
  stacks=()
  for d in */; do
    d="${d%/}"
    [[ " ${ORDER[*]} " == *" $d "* ]] || stacks+=("$d")
  done
  for (( i=${#ORDER[@]}-1; i>=0; i-- )); do stacks+=("${ORDER[$i]}"); done
fi

for s in "${stacks[@]}"; do
  if [ ! -f "$s/docker-compose.yaml" ]; then
    echo "-- skipping $s (no docker-compose.yaml)"
    continue
  fi
  echo "== down: $s"
  (cd "$s" && docker compose down)
done

echo "Done."
