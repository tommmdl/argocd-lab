#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/scripts/versions.env"
export PATH="$ROOT/.tools/bin:$PATH"
# Always target this lab, regardless of the user's current kubectl context.
CLUSTER_NAME=${CLUSTER_NAME:-lab}
KUBE_CONTEXT="kind-$CLUSTER_NAME"
lab_kubectl() { kubectl --context "$KUBE_CONTEXT" "$@"; }
