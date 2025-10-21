# Single Executable Deployment

The `deploy.sh` script is a single executable that automatically detects your environment and deploys the entire MongoDB Enterprise Advanced setup.

## 🚀 One-Command Deployment

```bash
# Make executable and run
chmod +x deploy.sh
./deploy.sh
```

## 📋 What It Does Automatically

✅ **Environment Detection**: Automatically detects OS (Ubuntu, macOS, etc.)  
✅ **Configuration Validation**: Checks and validates all required settings  
✅ **Prerequisites Check**: Verifies all required tools are installed  
✅ **Kubernetes Detection**: Auto-detects your Kubernetes cluster context  
✅ **Complete Deployment**: Deploys everything in the correct order  
✅ **Status Verification**: Waits for each component to be ready  
✅ **Connection Info**: Provides ready-to-use connection strings  

## 🔧 Configuration

### First Run
1. Run `./deploy.sh`
2. It creates a `deploy.conf` file with default settings
3. Edit `deploy.conf` with your passwords and preferences
4. Run `./deploy.sh` again

### Configuration File (`deploy.conf`)
```json
{
  "environment": {
    "os": "auto",
    "k8s_context": "auto",
    "mongodb_namespace": "mongodb",
    "mongodb_resource_name": "mdb-rs",
    "mongodb_version": "8.2.1-ent"
  },
  "passwords": {
    "admin_password": "your-secure-admin-password",
    "user_password": "your-secure-user-password", 
    "search_sync_password": "your-secure-search-password"
  },
  "resources": {
    "mongodb_cpu_limit": "2",
    "mongodb_memory_limit": "2Gi",
    "search_cpu_limit": "3",
    "search_memory_limit": "5Gi"
  },
  "ops_manager": {
    "enabled": true,
    "project_name": "search-project"
  }
}
```

## 🎯 Auto-Detection Features

### Operating System Detection
- **Ubuntu/Debian**: Uses apt packages
- **macOS**: Uses Homebrew packages  
- **RHEL/CentOS**: Uses yum packages
- **Generic Linux**: Fallback options

### Kubernetes Cluster Detection
- **minikube**: Auto-detects minikube context
- **kind**: Auto-detects kind clusters
- **Docker Desktop**: Auto-detects Docker Desktop K8s
- **microk8s**: Auto-detects microk8s
- **Custom**: Uses configured context

### Prerequisites Check
- **kubectl**: Kubernetes command-line tool
- **helm**: Package manager for Kubernetes
- **docker**: Container runtime
- **Kubernetes cluster**: Running and accessible

## 📊 Deployment Steps

The script automatically runs these steps in order:

1. **Configuration Validation** - Checks all required settings
2. **Environment Detection** - Detects OS and Kubernetes
3. **Prerequisites Check** - Verifies all tools are installed
4. **Operator Installation** - Installs MongoDB Kubernetes Operator
5. **Ops Manager Deployment** - Deploys MongoDB Ops Manager
6. **MongoDB Enterprise Deployment** - Deploys MongoDB Enterprise Advanced
7. **User Creation** - Creates required MongoDB users
8. **Search Deployment** - Deploys MongoDB Search & Vector Search
9. **Verification** - Waits for all components to be ready
10. **Summary** - Provides connection information

## 🔍 Smart Error Handling

### Missing Configuration
```bash
❌ admin_password is required in deploy.conf
⚠️  Please edit deploy.conf and configure your passwords and settings
```

### Missing Prerequisites
```bash
❌ Missing required tools: kubectl helm docker
ℹ️  Please install missing tools and run this script again
```

### Kubernetes Issues
```bash
❌ Kubernetes cluster is not accessible
ℹ️  Please ensure your cluster is running and accessible
```

## 🎉 Deployment Success

After successful deployment, you get:

```
🎉 MongoDB Enterprise Advanced with Search is ready!

📊 Deployment Summary:
   Kubernetes Context: minikube
   Namespace: mongodb
   MongoDB Resource: mdb-rs
   MongoDB Version: 8.2.1-ent

🔗 Access Information:
   MongoDB Connection:
   mongodb://mdb-user:password@mdb-rs-svc.mongodb.svc.cluster.local:27017/searchdb?replicaSet=mdb-rs

   Ops Manager:
   kubectl port-forward -n mongodb service/ops-manager-service 8080:8080
   Then open: http://localhost:8080

📋 Useful Commands:
   kubectl get pods -n mongodb
   kubectl get mdb -n mongodb
   kubectl get mdbs -n mongodb
```

## 🔧 Advanced Configuration

### Custom Resource Limits
```json
{
  "resources": {
    "mongodb_cpu_limit": "4",
    "mongodb_memory_limit": "8Gi",
    "search_cpu_limit": "6",
    "search_memory_limit": "12Gi"
  }
}
```

### Custom Kubernetes Context
```json
{
  "environment": {
    "k8s_context": "my-custom-cluster"
  }
}
```

### Disable Ops Manager
```json
{
  "ops_manager": {
    "enabled": false
  }
}
```

## 🚀 Quick Start Examples

### Ubuntu with minikube
```bash
# Install prerequisites
./setup-ubuntu-prerequisites.sh

# Start minikube
minikube start

# Deploy everything
./deploy.sh
```

### macOS with Docker Desktop
```bash
# Enable Kubernetes in Docker Desktop
# Then deploy
./deploy.sh
```

### Custom Kubernetes Cluster
```bash
# Edit deploy.conf with your cluster context
# Then deploy
./deploy.sh
```

## 🛠️ Troubleshooting

### Check Deployment Status
```bash
kubectl get pods -n mongodb
kubectl get mdb -n mongodb
kubectl get mdbs -n mongodb
```

### View Logs
```bash
kubectl logs -n mongodb deployment/mongodb-kubernetes-operator
kubectl logs -n mongodb mdb-rs-0 -c mongodb-enterprise-database
```

### Restart Deployment
```bash
# Delete and redeploy
kubectl delete namespace mongodb
./deploy.sh
```

## 📝 Benefits

✅ **Single Command**: One script does everything  
✅ **Auto-Detection**: No manual configuration needed  
✅ **Error Handling**: Clear error messages and solutions  
✅ **Validation**: Checks everything before deployment  
✅ **Progress Tracking**: Shows deployment progress  
✅ **Connection Info**: Provides ready-to-use strings  
✅ **Cross-Platform**: Works on Ubuntu, macOS, etc.  
✅ **Idempotent**: Safe to run multiple times  

This single executable approach makes deployment much simpler and more reliable!

