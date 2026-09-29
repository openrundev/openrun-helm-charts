#!/usr/bin/env bash
# Run against a local test cluster. Requires helm, kubectl and python3.
set -euo pipefail

: "${KUBE_REGISTRY_URL:?Set KUBE_REGISTRY_URL to a registry reachable by cluster nodes and build pods}"
CHART_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENRUN_REPO="${OPENRUN_REPO:-$CHART_ROOT/../openrun}"
TEST_NAMESPACE="helm-smoke-$(date +%s)-$$"
EXTERNAL_NAMESPACE="${TEST_NAMESPACE}-ext"
TEST_RELEASE="$TEST_NAMESPACE"
TEST_SERVER="${TEST_RELEASE}-openrun"
TEST_LOG_DIR="$(mktemp -d)"
CREATED_NAMESPACE=false
CREATED_EXTERNAL_NAMESPACE=false

cleanup() {
  local status=$?
  trap - EXIT
  if [ "$status" -ne 0 ]; then
    kubectl -n "$TEST_NAMESPACE" get pods,jobs || true
    echo "Integration test failed; logs: $TEST_LOG_DIR" >&2
  fi
  if [ "$CREATED_EXTERNAL_NAMESPACE" = true ]; then
    helm uninstall "$EXTERNAL_NAMESPACE" -n "$EXTERNAL_NAMESPACE" > /dev/null 2>&1 || true
    kubectl delete namespace "$EXTERNAL_NAMESPACE" "${EXTERNAL_NAMESPACE}-apps" --ignore-not-found --wait=false > /dev/null || true
  fi
  if [ "$CREATED_NAMESPACE" = true ]; then
    helm uninstall "$TEST_RELEASE" -n "$TEST_NAMESPACE" > /dev/null 2>&1 || true
    kubectl delete namespace "$TEST_NAMESPACE" "${TEST_NAMESPACE}-apps" --ignore-not-found --wait=false > /dev/null || true
  fi
  if [ "$status" -eq 0 ]; then
    rm -rf "$TEST_LOG_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT

server_pod() {
  kubectl -n "$TEST_NAMESPACE" get pods \
    -l "app.kubernetes.io/instance=$TEST_RELEASE,app.kubernetes.io/component=server" -o json |
    python3 -c 'import json,sys; pods=json.load(sys.stdin)["items"]; print(next(p["metadata"]["name"] for p in pods if not p["metadata"].get("deletionTimestamp") and any(c["type"] == "Ready" and c["status"] == "True" for c in p["status"].get("conditions", []))))'
}

server() {
  kubectl -n "$TEST_NAMESPACE" exec "$(server_pod)" -c openrun -- "$@"
}

admin_hash() {
  kubectl -n "$TEST_NAMESPACE" get secret "${TEST_SERVER}-config" -o json |
    python3 -c 'import base64,json,re,sys; c=base64.b64decode(json.load(sys.stdin)["data"]["openrun.toml"]).decode(); print(re.search(r"admin_password_bcrypt = \"([^\"]+)\"", c).group(1))'
}

check_app() {
  for attempt in $(seq 1 30); do
    if [ "$(server wget -qO- http://localhost/smoke 2>/dev/null)" = hello ]; then
      return
    fi
    sleep 2
  done
  echo "Application did not respond with hello" >&2
  return 1
}

# Fail before creating cluster resources if the fixture is unavailable.
test -f "$OPENRUN_REPO/tests/flask.py"
kubectl create namespace "$TEST_NAMESPACE" > /dev/null
CREATED_NAMESPACE=true

echo "Installing in $TEST_NAMESPACE with registry $KUBE_REGISTRY_URL"
helm install "$TEST_RELEASE" "$CHART_ROOT/charts/openrun" -n "$TEST_NAMESPACE" \
  --set-string config.registry.url="$KUBE_REGISTRY_URL" \
  --set config.system.defaultDomain=localhost --set service.type=ClusterIP \
  --wait --timeout 5m > "$TEST_LOG_DIR/install.log" 2>&1
INITIAL_ADMIN_HASH="$(admin_hash)"
INITIAL_DB_KEY="$(kubectl -n "$TEST_NAMESPACE" get secret "${TEST_SERVER}-db-secrets-key" -o jsonpath='{.data.key}')"
server openrun secret create --name chart_smoke --value survives-upgrade > /dev/null

echo "Building and deploying the Flask fixture from $OPENRUN_REPO"
server mkdir -p /tmp/chart-smoke
kubectl -n "$TEST_NAMESPACE" exec -i "$(server_pod)" -c openrun -- \
  sh -c 'cat > /tmp/chart-smoke/app.py' < "$OPENRUN_REPO/tests/flask.py"
server openrun app create --stage-at path --spec python-flask --auth none \
  --approve /tmp/chart-smoke /smoke > "$TEST_LOG_DIR/app-create.log" 2>&1
check_app
kubectl -n "${TEST_NAMESPACE}-apps" get deployments -o json |
  python3 -c 'import json,os,sys; images=[c["image"] for d in json.load(sys.stdin)["items"] for c in d["spec"]["template"]["spec"]["containers"]]; assert images and all(i.startswith(os.environ["KUBE_REGISTRY_URL"]+"/") for i in images), images'

echo "Upgrading immediately with a changed database name and service port"
helm upgrade "$TEST_RELEASE" "$CHART_ROOT/charts/openrun" -n "$TEST_NAMESPACE" --reuse-values \
  --set config.metadata.fsDatabase=smoke_fs_v2 --set postgres.service.port=5544 \
  --wait --timeout 3m > "$TEST_LOG_DIR/upgrade.log" 2>&1
kubectl -n "$TEST_NAMESPACE" wait --for=condition=complete "job/${TEST_SERVER}-db-init-2" --timeout=60s > /dev/null
test "$INITIAL_ADMIN_HASH" = "$(admin_hash)"
test "$INITIAL_DB_KEY" = "$(kubectl -n "$TEST_NAMESPACE" get secret "${TEST_SERVER}-db-secrets-key" -o jsonpath='{.data.key}')"
test "$(server openrun secret show --reveal chart_smoke)" = survives-upgrade
check_app

echo "Checking a second immediate upgrade with two server replicas"
helm upgrade "$TEST_RELEASE" "$CHART_ROOT/charts/openrun" -n "$TEST_NAMESPACE" --reuse-values \
  --set replicaCount=2 --wait --timeout 3m > "$TEST_LOG_DIR/upgrade-again.log" 2>&1
kubectl -n "$TEST_NAMESPACE" wait --for=condition=complete "job/${TEST_SERVER}-db-init-3" --timeout=60s > /dev/null
test "$INITIAL_ADMIN_HASH" = "$(admin_hash)"
check_app

echo "Installing with an external database on a non-default port"
kubectl create namespace "$EXTERNAL_NAMESPACE" > /dev/null
CREATED_EXTERNAL_NAMESPACE=true
helm install "$EXTERNAL_NAMESPACE" "$CHART_ROOT/charts/openrun" -n "$EXTERNAL_NAMESPACE" \
  --set-string config.registry.url="$KUBE_REGISTRY_URL" --set service.type=ClusterIP \
  --set postgres.enabled=false --set externalDatabase.enabled=true \
  --set-string externalDatabase.host="openrun-db.${TEST_NAMESPACE}.svc.cluster.local" \
  --set externalDatabase.port=5544 --set externalDatabase.username=postgres \
  --set externalDatabase.password=postgres --wait --timeout 3m > "$TEST_LOG_DIR/external.log" 2>&1

echo "PASS: application build/push, install, upgrades, credential retention, replicas and external database"
