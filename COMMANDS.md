# ArgoCD + Kustomize Lab

Portuguese version: [COMANDOS.md](COMANDOS.md)

## 1. Get the repository
Steps 1 to 5 work against github.com/tommmdl/argocd-lab in read-only mode:
the repoURL in apps/ already points to it and ArgoCD only needs to clone it.
git clone https://github.com/tommmdl/argocd-lab.git
cd argocd-lab

Step 6 (change through Git) requires a push, so you need your own fork, with
the repoURL in apps/ pointing to it:
gh repo fork tommmdl/argocd-lab --clone
cd argocd-lab
sed -i 's#github.com/tommmdl/argocd-lab#github.com/YOUR_USER/argocd-lab#' apps/app-dev.yaml apps/app-prod.yaml appsets/lab.yaml
git commit -am "point apps to the fork" && git push
# if the Applications were already created, reapply: kubectl apply -f apps/

## 2. Cluster and ArgoCD
kind create cluster --name lab
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# server-side is required: the applicationsets CRD exceeds the 262144-byte limit
# of the last-applied-configuration annotation used by client-side apply
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
kubectl port-forward -n argocd svc/argocd-server 8080:443

## 3. Create the two Applications
kubectl apply -f apps/app-dev.yaml
kubectl apply -f apps/app-prod.yaml
kubectl -n argocd get applications

## 4. Test drift WITHOUT self-heal (lab-dev)
kubectl -n lab-dev scale deploy/dev-web --replicas=5
kubectl -n argocd get application lab-dev -o jsonpath='{.status.sync.status}'; echo
# OutOfSync: ArgoCD reports the drift but does not fix it

## 5. Test drift WITH self-heal (lab-prod)
kubectl -n lab-prod scale deploy/prod-web --replicas=9
sleep 25
kubectl -n lab-prod get deploy prod-web
# goes back to 3 on its own

## 6. Test a change through Git (the correct flow)
# edit overlays/prod/kustomization.yaml -> replicas 5
git commit -am "prod to 5 replicas" && git push
# ArgoCD reconciles on its own within 3 minutes, or force it:
kubectl -n argocd patch application lab-prod --type merge -p '{"operation":{"sync":{}}}'

## 7. See what Kustomize generates, without a cluster
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod

## 8. Same lab with an ApplicationSet (optional)
# appsets/lab.yaml generates lab-dev and lab-prod from one template;
# it replaces the two Applications in apps/, use one or the other
kubectl -n argocd delete application lab-dev lab-prod
# the Applications in apps/ have no finalizer, so the workloads stay
kubectl apply -f appsets/lab.yaml
kubectl -n argocd get applicationset lab
kubectl -n argocd get applications
# wait for Succeeded before repeating steps 4 and 5: a new Application
# auto-syncs once even without self-heal, and that would undo the drift in lab-dev
kubectl -n argocd get application lab-dev -o jsonpath='{.status.operationState.phase}'; echo
# to go back (preserveResourcesOnDeletion keeps the workloads):
kubectl -n argocd delete applicationset lab
kubectl apply -f apps/

## 9. See sync waves and hooks
# every full sync runs: PreSync migrate -> Service (wave 0) -> Deployment (wave 1) -> PostSync smoke-test
kubectl -n argocd patch application lab-dev --type merge -p '{"operation":{"sync":{}}}'
kubectl -n argocd get application lab-dev -o jsonpath='{range .status.operationState.syncResult.resources[*]}{.syncPhase}{"\t"}{.kind}{"\t"}{.name}{"\n"}{end}'
kubectl -n lab-dev get jobs
kubectl -n lab-dev logs job/dev-migrate
kubectl -n lab-dev logs job/dev-smoke-test
# the smoke test fails when the Service has no endpoints, and the sync fails with it.
# self-heal does NOT run hooks: it only syncs what drifted
kubectl -n lab-prod scale deploy/prod-web --replicas=9
sleep 25
kubectl -n lab-prod get jobs
# same jobs, same age: only the Deployment was synced
