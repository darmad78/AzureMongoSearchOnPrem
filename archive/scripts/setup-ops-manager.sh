#!/bin/bash

# MongoDB Ops Manager Setup Script
# Downloads and deploys Ops Manager for MongoDB Enterprise Advanced

set -e

echo "🔧 Setting up MongoDB Ops Manager..."

# Environment variables
export K8S_CTX="docker-desktop"
export MDB_NS="mongodb"
export OPS_MANAGER_TAR="mongodb-mms-8.0.15.500.20251015T2125Z.tar.gz"
export OPS_MANAGER_URL="https://downloads.mongodb.com/on-prem-mms/tar/mongodb-mms-8.0.15.500.20251015T2125Z.tar.gz"

# Create Ops Manager directory
mkdir -p ops-manager

# Download Ops Manager if not exists
if [ ! -f "ops-manager/$OPS_MANAGER_TAR" ]; then
    echo "📥 Downloading MongoDB Ops Manager..."
    curl -L -o "ops-manager/$OPS_MANAGER_TAR" "$OPS_MANAGER_URL"
else
    echo "✅ Ops Manager tar file already exists"
fi

# Extract Ops Manager
echo "📦 Extracting Ops Manager..."
cd ops-manager
tar -xzf "$OPS_MANAGER_TAR"
cd ..

# Create Ops Manager Kubernetes manifests
echo "📝 Creating Ops Manager Kubernetes manifests..."

# Create Ops Manager ConfigMap
cat > k8s/ops-manager-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: om-project
  namespace: $MDB_NS
data:
  projectName: "search-project"
  orgId: "search-org"
EOF

# Create Ops Manager Credentials Secret
cat > k8s/ops-manager-credentials.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: om-credentials
  namespace: $MDB_NS
type: Opaque
stringData:
  user: "admin"
  publicApiKey: "your-public-api-key"
  privateApiKey: "your-private-api-key"
EOF

# Create Ops Manager Deployment
cat > k8s/ops-manager-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb-ops-manager
  namespace: $MDB_NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongodb-ops-manager
  template:
    metadata:
      labels:
        app: mongodb-ops-manager
    spec:
      containers:
      - name: ops-manager
        image: quay.io/mongodb/mongodb-enterprise-ops-manager-ubi:8.0.15
        ports:
        - containerPort: 8080
        env:
        - name: MMS_INITDB_ROOT_USERNAME
          value: "admin"
        - name: MMS_INITDB_ROOT_PASSWORD
          value: "admin123"
        - name: MMS_INITDB_DATABASE
          value: "mms"
        resources:
          requests:
            memory: "2Gi"
            cpu: "1"
          limits:
            memory: "4Gi"
            cpu: "2"
        volumeMounts:
        - name: ops-manager-data
          mountPath: /data
      volumes:
      - name: ops-manager-data
        persistentVolumeClaim:
          claimName: ops-manager-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ops-manager-pvc
  namespace: $MDB_NS
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: ops-manager-service
  namespace: $MDB_NS
spec:
  selector:
    app: mongodb-ops-manager
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
  type: LoadBalancer
EOF

# Apply Ops Manager manifests
echo "🚀 Deploying Ops Manager to Kubernetes..."
kubectl apply -f k8s/ops-manager-configmap.yaml
kubectl apply -f k8s/ops-manager-credentials.yaml
kubectl apply -f k8s/ops-manager-deployment.yaml

echo "⏳ Waiting for Ops Manager to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/mongodb-ops-manager -n $MDB_NS

echo "✅ MongoDB Ops Manager deployed successfully!"
echo ""
echo "🔗 Access Ops Manager:"
echo "   kubectl port-forward -n $MDB_NS service/ops-manager-service 8080:8080"
echo "   Then open: http://localhost:8080"
echo ""
echo "📝 Default credentials:"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "🔧 Next steps:"
echo "   1. Access Ops Manager and create API keys"
echo "   2. Update the credentials in k8s/ops-manager-credentials.yaml"
echo "   3. Run setup-mongodb.sh to deploy MongoDB Enterprise"

