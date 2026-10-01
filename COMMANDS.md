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
sed -i 's#github.com/tommmdl/argocd-lab#github.com/YOUR_USER/argocd-lab#' apps/app-dev.yaml apps/app-prod.yaml
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
