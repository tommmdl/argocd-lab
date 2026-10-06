# ArgoCD + Kustomize Lab

Portuguese version: [COMANDOS.md](COMANDOS.md)

## 1. Get the repository

For read-only experiments, clone this repository. For changes through Git (step 6), use your own fork instead and update all three repoURL references before creating Applications.

```bash
git clone https://github.com/tommmdl/argocd-lab.git
cd argocd-lab
```

Alternatively, start with a fork:

```bash
gh repo fork tommmdl/argocd-lab --clone
cd argocd-lab
sed -i 's#github.com/tommmdl/argocd-lab#github.com/YOUR_USER/argocd-lab#' apps/app-dev.yaml apps/app-prod.yaml appsets/lab.yaml
git commit -am "point apps to the fork"
git push
```

Replace YOUR_USER with your GitHub username. On macOS, use `sed -i ''` instead of `sed -i`.

## 2. Install tools and create the lab

Prerequisites: a running Docker daemon, Bash, curl, tar, Python 3 and make (Linux, macOS or WSL). The tools are installed inside the repository. Setup creates the cluster and installs Argo CD; it does not create the Applications. Scripts always use context `kind-lab`. Use that context explicitly for the commands below.

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r scripts/requirements.txt
make tools
export PATH="$PWD/.tools/bin:$PATH"
make validate
make setup
kubectl config use-context kind-lab
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

## 3. Create Applications and wait for the first sync

Run in a second terminal with the same PATH and context. Expected: both Applications are Synced and Healthy, the sync phase is Succeeded when an operation was needed, dev has 1 replica and prod has 3. A new OutOfSync Application can perform an automated sync even with self-heal disabled: wait before testing drift. Already matching workloads can be Synced/Healthy without any operation history.

```bash
kubectl apply -f apps/
make wait-sync
make status
```

## 4. Test drift WITHOUT self-heal

Expected: lab-dev becomes OutOfSync and keeps 5 replicas. Detection is asynchronous, so wait for the status instead of reading it immediately.

```bash
kubectl -n lab-dev scale deployment/dev-web --replicas=5
kubectl -n argocd wait application/lab-dev \
  --for=jsonpath='{.status.sync.status}'=OutOfSync --timeout=120s
kubectl -n lab-dev get deployment dev-web
```

## 5. Test drift WITH self-heal

Expected: prod returns to the replica count in Git (initially 3). If you have already changed it in step 6, use the new value in the wait command.

```bash
kubectl -n lab-prod scale deployment/prod-web --replicas=9
kubectl -n lab-prod wait deployment/prod-web \
  --for=jsonpath='{.spec.replicas}'=3 --timeout=120s
kubectl -n lab-prod get deployment prod-web
```

## 6. Change through Git

In your fork, edit the replica patch in overlays/prod/kustomization.yaml from 3 to 5, then validate, commit and push. Expected: Argo CD applies 5 replicas and keeps them. Request a refresh to avoid waiting for the Git polling interval; automated sync performs the deployment.

```bash
make validate
git add overlays/prod/kustomization.yaml
git commit -m "prod to 5 replicas"
git push
kubectl -n argocd annotate application lab-prod argocd.argoproj.io/refresh=hard --overwrite
kubectl -n lab-prod wait deployment/prod-web \
  --for=jsonpath='{.spec.replicas}'=5 --timeout=300s
make wait-sync
```

## 7. Render and validate without a cluster

Validation renders both overlays and checks workloads, practice manifests, Applications and ApplicationSet. Argo CD schemas are extracted from the pinned release CRDs. Missing schemas and unknown fields fail validation; behavioral mistakes in the practice examples remain intentional. Schema validation cannot verify controller behavior or resource availability.

```bash
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod
make validate
```

## 8. Use ApplicationSet (optional)

Use Applications or ApplicationSet, one at a time. Restore dev to 1 replica before switching. The handwritten Applications have no deletion finalizer, so their workloads remain. Wait for the generated Applications to be Synced/Healthy. If preserved workloads already match Git, no new sync occurs. Before testing drift, explicitly sync both Applications to record the current revision; otherwise the first drift can trigger an initial automated sync even with self-heal disabled. preserveResourcesOnDeletion keeps workloads when deleting this ApplicationSet.

```bash
kubectl -n lab-dev scale deployment/dev-web --replicas=1
make wait-sync
kubectl -n argocd delete application lab-dev lab-prod
kubectl apply -f appsets/lab.yaml
make wait-sync
for app in lab-dev lab-prod; do
  kubectl -n argocd patch application "$app" --type merge -p '{"operation":{"sync":{}}}'
  kubectl -n argocd wait "application/$app" \
    --for=jsonpath='{.status.operationState.phase}'=Succeeded --timeout=300s
done
make wait-sync
make status
```

To return to handwritten Applications:

```bash
kubectl -n argocd delete applicationset lab
kubectl apply -f apps/
make wait-sync
```

## 9. Inspect sync waves and hooks

A full sync runs PreSync migrate → Service (wave 0) → Deployment (wave 1) → PostSync smoke-test. The smoke test calls the Service. Request a full sync, then wait for a new operation to start and finish before reading its results. Self-heal of replica drift does not rerun these hooks; inspect Job creation times before and after repeating step 5.

```bash
previous=$(kubectl -n argocd get application lab-dev -o jsonpath='{.status.operationState.startedAt}')
kubectl -n argocd patch application lab-dev --type merge -p '{"operation":{"sync":{}}}'
for attempt in {1..60}; do
  current=$(kubectl -n argocd get application lab-dev -o jsonpath='{.status.operationState.startedAt}')
  if [ "$current" != "$previous" ]; then break; fi
  sleep 2
done
[ "$current" != "$previous" ] || { echo "Sync did not start"; exit 1; }
bash scripts/wait-sync.sh lab-dev
kubectl -n argocd get application lab-dev \
  -o jsonpath='{range .status.operationState.syncResult.resources[*]}{.syncPhase}{"\t"}{.kind}{"\t"}{.name}{"\n"}{end}'
kubectl -n lab-dev get jobs
kubectl -n lab-dev logs job/dev-migrate
kubectl -n lab-dev logs job/dev-smoke-test
```

## Troubleshooting

If a wait times out, inspect status, events and hook logs:

```bash
make status
kubectl -n argocd get application lab-dev -o yaml
kubectl -n lab-dev get events --sort-by=.metadata.creationTimestamp
kubectl -n lab-dev logs job/dev-migrate
kubectl -n lab-dev logs job/dev-smoke-test
```

Setup reuses a cluster named lab if it already exists; it does not upgrade existing nodes. To reproduce the pinned node version, use a fresh cluster. Without make, run the corresponding `bash scripts/*.sh` command from the Makefile.

## Cleanup

This deletes the lab cluster and its workloads.

```bash
.tools/bin/kind delete cluster --name lab
```
