#!/usr/bin/env bash
# Starts a local Perses instance wired to the remote Thanos querier.
#
# Usage:
#   ./start.sh [start]                 # uses KUBECONFIG env var
#   ./start.sh /path/to/kubeconfig     # uses the given kubeconfig
#   ./start.sh stop                    # stops the stack

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# "start" is an accepted no-op keyword so callers can be explicit
if [[ "${1:-}" == "start" ]]; then
  shift
fi

KUBECONFIG="${1:-${KUBECONFIG:-}}"

if [[ "${1:-}" == "stop" ]]; then
  echo "Stopping Perses stack..."
  for CMD in "docker compose" "podman compose" "podman-compose"; do
    if $CMD -f "$SCRIPT_DIR/docker-compose.yaml" down 2>/dev/null; then break; fi
  done
  exit 0
fi

# ── Resolve kubeconfig ────────────────────────────────────────────────────────
if [[ -z "$KUBECONFIG" ]]; then
  echo "ERROR: KUBECONFIG is not set. Pass it as an argument or export it."
  exit 1
fi
export KUBECONFIG

# ── Obtain Bearer token ───────────────────────────────────────────────────────
echo "Obtaining Bearer token..."
TOKEN=$(oc whoami -t 2>/dev/null || kubectl create token default -n openshift-monitoring --duration=24h 2>/dev/null || true)
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: Could not obtain a Bearer token. Make sure 'oc' is logged in or 'kubectl' has access."
  exit 1
fi
echo "Token obtained (${#TOKEN} chars)."

# ── Resolve Thanos querier host ───────────────────────────────────────────────
echo "Resolving Thanos querier route..."
THANOS_HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [[ -z "$THANOS_HOST" ]]; then
  echo "ERROR: Could not resolve the Thanos querier route. Make sure 'oc' is logged in and the route exists."
  exit 1
fi
echo "Thanos host: ${THANOS_HOST}"

# ── Generate nginx.conf from template ────────────────────────────────────────
echo "Generating nginx.conf..."
sed \
  -e "s/THANOS_HOST_PLACEHOLDER/${THANOS_HOST}/g" \
  -e "s/BEARER_TOKEN_PLACEHOLDER/${TOKEN}/g" \
  "$SCRIPT_DIR/nginx.conf.tmpl" > "$SCRIPT_DIR/nginx.conf"
echo "nginx.conf written."

# ── Pick container engine (docker or podman) ──────────────────────────────────
if command -v docker &>/dev/null; then
  COMPOSE_CMD="docker compose"
elif command -v podman-compose &>/dev/null; then
  COMPOSE_CMD="podman-compose"
elif command -v podman &>/dev/null && podman compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="podman compose"
else
  echo "ERROR: Neither 'docker compose' nor 'podman-compose' found."
  exit 1
fi

# ── Start the stack ───────────────────────────────────────────────────────────
echo "Starting Perses stack ($COMPOSE_CMD)..."
$COMPOSE_CMD -f "$SCRIPT_DIR/docker-compose.yaml" up -d

echo ""
echo "Perses is starting at http://localhost:8080"
echo "Dashboard: http://localhost:8080/projects/descheduler/dashboards/memory-aware-rebalancing"
echo ""
echo "To stop:          $0 stop"
echo "To refresh token: $0 start"