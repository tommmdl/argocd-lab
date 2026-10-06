#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
apps=("$@")
if ((${#apps[@]} == 0)); then apps=(lab-dev lab-prod); fi
for app in "${apps[@]}"; do
  # ApplicationSet creates Applications asynchronously.
  for attempt in {1..60}; do
    if lab_kubectl -n argocd get application "$app" >/dev/null 2>&1; then break; fi
    sleep 2
  done
  lab_kubectl -n argocd wait "application/$app" \
    --for=jsonpath='{.status.sync.status}'=Synced --timeout=300s
  lab_kubectl -n argocd wait "application/$app" \
    --for=jsonpath='{.status.health.status}'=Healthy --timeout=300s
  phase=$(lab_kubectl -n argocd get application "$app" -o jsonpath='{.status.operationState.phase}')
  pending=$(lab_kubectl -n argocd get application "$app" -o jsonpath='{.operation}')
  # Already matching workloads need no sync operation, e.g. after switching
  # from Applications to ApplicationSet while preserving resources.
  if [[ -n "$phase" || -n "$pending" ]]; then
    lab_kubectl -n argocd wait "application/$app" \
      --for=jsonpath='{.status.operationState.phase}'=Succeeded --timeout=300s
  fi
done
