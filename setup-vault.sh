#!/bin/bash
set -e

VAULT_DIR="/run/media/tmquang/Docker/k8s/volumes/vault"

echo "=== Prepare volume directory ==="
sudo mkdir -p $VAULT_DIR
sudo chown -R 100:1000 $VAULT_DIR
sudo chmod -R 750 $VAULT_DIR

echo "=== Add Helm repo ==="
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

echo "=== Create namespace ==="
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

echo "=== Create PersistentVolume ==="
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: vault-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: $VAULT_DIR
EOF

echo "=== Install Vault via Helm ==="
helm install vault hashicorp/vault \
  --namespace vault \
  --set "server.dataStorage.enabled=true" \
  --set "server.dataStorage.size=10Gi" \
  --set "server.dataStorage.storageClass=null" \
  --set "server.standalone.enabled=true" \
  --set "server.ingress.enabled=true" \
  --set "server.ingress.ingressClassName=nginx" \
  --set "server.ingress.hosts[0].host=vault.192.168.62.103.nip.io" \
  --set "server.ingress.hosts[0].paths[0]=/" \
  --set "ui.enabled=true" \
  --set "ui.serviceType=NodePort" \
  --set "ui.serviceNodePort=30082"

echo "=== Waiting for Vault pod to be ready ==="
kubectl -n vault rollout status statefulset/vault --timeout=120s

echo "=== Initialize Vault ==="
echo "Waiting 15s..."
sleep 15

kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > /tmp/vault-init.json

echo "=== Vault Init Keys (SAVE THESE!) ==="
cat /tmp/vault-init.json

echo "=== Auto unseal Vault (using first 3 keys) ==="
KEY1=$(cat /tmp/vault-init.json | grep -o '"unseal_keys_b64":\["[^"]*"' | head -1 | cut -d'"' -f4)
KEYS=$(cat /tmp/vault-init.json | python3 -c "import sys,json; d=json.load(sys.stdin); [print(k) for k in d['unseal_keys_b64'][:3]]")

while IFS= read -r key; do
  kubectl exec -n vault vault-0 -- vault operator unseal "$key"
done <<< "$KEYS"

echo "=== Vault Status ==="
kubectl exec -n vault vault-0 -- vault status

echo "=== Root Token ==="
ROOT_TOKEN=$(cat /tmp/vault-init.json | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")
echo "Root Token: $ROOT_TOKEN"

echo "=== Enable userpass auth ==="
kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN"
kubectl exec -n vault vault-0 -- vault auth enable userpass
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

echo "=== Create admin user ==="
kubectl exec -n vault vault-0 -- vault write auth/userpass/users/admin \
  password=admin123 \
  policies=admins

echo "=== Create dev policy ==="
kubectl exec -n vault vault-0 -- vault policy write dev-policy - <<POLICY
path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/*" {
  capabilities = ["list"]
}
POLICY

echo "=== Done! ==="
echo "Access Vault UI at: https://vault.192.168.62.103.nip.io:31071"
echo "Or via NodePort:    http://192.168.62.103:30082"
echo "Root token saved at: /tmp/vault-init.json"
echo ""
echo "⚠️  IMPORTANT: Save /tmp/vault-init.json to a safe place!"
cp /tmp/vault-init.json ~/vault-init-backup.json
echo "Backup saved to: ~/vault-init-backup.json"
