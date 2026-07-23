#!/usr/bin/env bash
# One-time migration: delete the old-named networks and recreate them under the
# nestlab-* names, sourcing all subnets/gateways/parents from .env.
# Run from the stacks/ folder on the Docker host:  bash migrate-networks.sh
set -uo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a

STACKS=(proxy sql mqtt ha downloaders arr media)

echo ">> 1. Bringing all stacks down (detaches containers from networks)..."
for s in "${STACKS[@]}"; do
  docker compose -f "compose-$s.yml" down || true
done

echo ">> 2. Removing old networks..."
# Old external bridges (exact names, from your docker network inspect):
for n in sbh-nas-net-proxy sbh-nas-net-download sbh-nas-net-mqtt sbh-nas-net-sys netlab-sql; do
  docker network rm "$n" 2>/dev/null && echo "  removed $n" || echo "  skip $n (absent or still in use)"
done
# Old compose-managed macvlans (may be project-prefixed, e.g. stacks_iot-net):
for n in iot-net sbh-net srv-net; do
  docker network rm "$n" 2>/dev/null && echo "  removed $n" || echo "  skip $n (absent or project-prefixed)"
done
echo "   If any old macvlan lingers, find it with: docker network ls --filter driver=macvlan"

echo ">> 3. Creating bridge externals..."
docker network create -d bridge --subnet "$PROXY_SUBNET"    --gateway "$PROXY_GATEWAY"    "$NET_PROXY"
docker network create -d bridge --subnet "$DOWNLOAD_SUBNET" --gateway "$DOWNLOAD_GATEWAY" "$NET_DOWNLOAD"
docker network create -d bridge --subnet "$MQTT_SUBNET"     --gateway "$MQTT_GATEWAY"     "$NET_MQTT"
docker network create -d bridge --subnet "$SYS_SUBNET"      --gateway "$SYS_GATEWAY"      "$NET_SYS"
docker network create -d bridge --subnet "$SQL_SUBNET"      --gateway "$SQL_GATEWAY"      "$NET_SQL"

echo ">> 4. Creating macvlan externals..."
docker network create -d macvlan -o parent="$LAN_PARENT" --subnet "$LAN_SUBNET"                          "$NET_LAN"
docker network create -d macvlan -o parent="$SRV_PARENT" --subnet "$SRV_SUBNET" --gateway "$SRV_GATEWAY" "$NET_SRV"
docker network create -d macvlan -o parent="$IOT_PARENT" --subnet "$IOT_SUBNET" --gateway "$IOT_GATEWAY" "$NET_IOT"

echo ">> 5. Bringing stacks back up..."
for s in "${STACKS[@]}"; do
  docker compose -f "compose-$s.yml" up -d
done

echo ">> Done. Current nestlab networks:"
docker network ls | grep -E 'NETWORK|nestlab'
