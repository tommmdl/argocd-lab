#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
cd "$ROOT"
command -v kubectl >/dev/null
command -v kubeconform >/dev/null
python3 -c 'import yaml'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 scripts/argocd-schemas.py "$ARGOCD_VERSION" "$tmp/schemas"
for env in dev prod; do
  kubectl kustomize "overlays/$env" > "$tmp/$env.yaml"
done
kubeconform -strict -summary -kubernetes-version "$KUBERNETES_VERSION" \
  "$tmp/dev.yaml" "$tmp/prod.yaml" pratica/
kubeconform -strict -summary \
  -schema-location "$tmp/schemas/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
  apps/ appsets/
