#!/usr/bin/env bash
# Validation script: K8s (with harness.io/track) -> Helm (without) on same Deployment.
# Uses existing GKE cluster gke_cd-play_us-west1_gitops-cluster11 (override with KUBE_CONTEXT).
# Run from repo root or from this directory (script detects path).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
KUBE_CONTEXT="${KUBE_CONTEXT:-gke_cd-play_us-west1_gitops-cluster11}"

echo "=== 1. Use GKE cluster ==="
kubectl config use-context "$KUBE_CONTEXT" || { echo "Failed to switch to context $KUBE_CONTEXT. List contexts: kubectl config get-contexts"; exit 1; }
kubectl cluster-info >/dev/null 2>&1 || { echo "Cannot reach cluster. Check gcloud/kubectl access."; exit 1; }
echo "Using context: $(kubectl config current-context)"

echo ""
echo "=== 2. Ensure namespace exists and deploy Phase 1 (K8s with harness.io/track: stable) ==="
NAMESPACE="${NAMESPACE:-validation-demo}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f phase1-k8s-with-harness-labels/deployment.yaml -n "$NAMESPACE"
kubectl rollout status deployment/demo-app -n "$NAMESPACE" --timeout=60s
echo "Phase 1 deployed. Selector includes harness.io/track: stable"
kubectl get deployment demo-app -n "$NAMESPACE" -o jsonpath='{.spec.selector.matchLabels}' && echo

echo ""
echo "=== 3. Try switching to Helm WITHOUT deleting Deployment (expect failure) ==="
if helm upgrade --install demo-app phase2-helm-no-harness-labels/ -n "$NAMESPACE" 2>&1; then
  echo "UNEXPECTED: Helm upgrade succeeded; we expected a selector mismatch error."
  exit 1
else
  echo "EXPECTED: Helm upgrade failed (selector/label mismatch)."
fi

echo ""
echo "=== 4. Force deploy: delete Deployment, then install with Helm ==="
kubectl delete deployment demo-app -n "$NAMESPACE" --ignore-not-found --wait=true
helm upgrade --install demo-app phase2-helm-no-harness-labels/ -n "$NAMESPACE"
kubectl rollout status deployment/demo-app -n "$NAMESPACE" --timeout=60s
echo "Success: Deployment now managed by Helm (no harness.io/track in selector)."
kubectl get deployment demo-app -n "$NAMESPACE" -o jsonpath='{.spec.selector.matchLabels}' && echo

echo ""
echo "=== Validation complete ==="
echo "Switching from K8s (with Harness labels) to Helm is supported when you do a force deploy (delete then deploy)."
