#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
command -v kind >/dev/null
command -v kubectl >/dev/null
docker info >/dev/null
if ! kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
  kind create cluster --name "$CLUSTER_NAME" --image "$KIND_NODE_IMAGE" --wait 120s
fi
lab_kubectl create namespace argocd --dry-run=client -o yaml | lab_kubectl apply -f -
lab_kubectl apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml"
lab_kubectl wait --for=condition=Established --timeout=120s \
  crd/applications.argoproj.io crd/applicationsets.argoproj.io
lab_kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
lab_kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
lab_kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
lab_kubectl -n argocd rollout status deployment/argocd-applicationset-controller --timeout=300s
printf 'Argo CD %s ready in context %s. Apply apps/ or appsets/lab.yaml next.\n' "$ARGOCD_VERSION" "$KUBE_CONTEXT"
