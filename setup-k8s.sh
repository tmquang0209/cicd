#!/bin/bash
set -e

DOCKER_PATH="/run/media/tmquang/Docker"
K8S_DIR="$DOCKER_PATH/k8s"

echo "=== Setup K8s data directories ==="
sudo mkdir -p $K8S_DIR/{etcd,containerd,kubelet,volumes}
sudo chmod 700 $K8S_DIR/etcd

echo "=== Install dependencies ==="
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg conntrack

echo "=== Install containerd ==="
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i "s|^root = .*|root = \"$K8S_DIR/containerd\"|" /etc/containerd/config.toml
sudo systemctl restart containerd

echo "=== Install kubeadm, kubelet, kubectl ==="
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "=== Move kubelet data dir to external disk ==="
sudo tee /etc/default/kubelet > /dev/null <<EOF
KUBELET_EXTRA_ARGS=--root-dir=$K8S_DIR/kubelet
EOF

echo "=== Pre-flight ==="
sudo swapoff -a
sudo modprobe br_netfilter
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

echo "=== Init cluster ==="
sudo tee /tmp/kubeadm-config.yaml > /dev/null <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
etcd:
  local:
    dataDir: $K8S_DIR/etcd
networking:
  podSubnet: 10.244.0.0/16
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
EOF

sudo kubeadm init --config /tmp/kubeadm-config.yaml

echo "=== Setup kubectl config ==="
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "=== Install Flannel CNI ==="
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo "=== Allow scheduling on master (single node) ==="
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

echo "=== Done! ==="
kubectl get nodes
kubectl get pods -A
