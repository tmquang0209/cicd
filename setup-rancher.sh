#!/bin/bash
set -e

DOCKER_PATH="/run/media/tmquang/Docker"

echo "=== Install Docker (Rancher cần Docker) ==="
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER

echo "=== Run Rancher container ==="
sudo docker run -d \
  --name rancher \
  --restart=unless-stopped \
  -p 80:80 \
  -p 443:443 \
  -v $DOCKER_PATH/rancher:/var/lib/rancher \
  --privileged \
  rancher/rancher:latest

echo "=== Chờ Rancher khởi động ==="
echo "Waiting 60s..."
sleep 60

echo "=== Lấy bootstrap password ==="
sudo docker logs rancher 2>&1 | grep "Bootstrap Password:"

echo "=== Done! ==="
echo "Truy cập: https://localhost hoặc https://$(hostname -I | awk '{print $1}')"
