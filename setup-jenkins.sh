#!/bin/bash
set -e

echo "=== Create Jenkins namespace ==="
kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

echo "=== Prepare volume directory ==="
sudo mkdir -p /run/media/tmquang/Docker/k8s/volumes/jenkins
sudo chown -R 1000:1000 /run/media/tmquang/Docker/k8s/volumes/jenkins

echo "=== Create PersistentVolume ==="
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jenkins-pv
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /run/media/tmquang/Docker/k8s/volumes/jenkins
EOF

echo "=== Create PersistentVolumeClaim ==="
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pvc
  namespace: jenkins
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
EOF

echo "=== Create ServiceAccount ==="
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins
  namespace: jenkins
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: jenkins
  namespace: jenkins
EOF

echo "=== Deploy Jenkins ==="
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins
  namespace: jenkins
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      serviceAccountName: jenkins
      securityContext:
        fsGroup: 1000
        runAsUser: 1000
      containers:
      - name: jenkins
        image: jenkins/jenkins:lts
        ports:
        - containerPort: 8080
        - containerPort: 50000
        volumeMounts:
        - name: jenkins-data
          mountPath: /var/jenkins_home
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
      volumes:
      - name: jenkins-data
        persistentVolumeClaim:
          claimName: jenkins-pvc
EOF

echo "=== Create Service ==="
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: jenkins
  namespace: jenkins
spec:
  type: NodePort
  selector:
    app: jenkins
  ports:
  - name: http
    port: 8080
    targetPort: 8080
    nodePort: 30080
  - name: agent
    port: 50000
    targetPort: 50000
    nodePort: 30050
EOF

echo "=== Create Ingress ==="
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins
  namespace: jenkins
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
spec:
  ingressClassName: nginx
  rules:
  - host: jenkins.192.168.62.103.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: jenkins
            port:
              number: 8080
EOF

echo "=== Waiting for Jenkins to be ready ==="
kubectl -n jenkins rollout status deploy/jenkins

echo "=== Waiting for Jenkins to initialize (60s) ==="
sleep 60

echo "=== Initial Admin Password ==="
kubectl exec -n jenkins deploy/jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword

echo "=== Done! ==="
echo "Access Jenkins at: https://jenkins.192.168.62.103.nip.io:31071"
echo "Or via NodePort:   http://192.168.62.103:30080"
