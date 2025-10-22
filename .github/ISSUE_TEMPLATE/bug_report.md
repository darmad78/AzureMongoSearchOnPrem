---
name: Bug Report
about: Create a report to help us improve
title: '[BUG] '
labels: bug
assignees: ''
---

**Describe the Bug**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected Behavior**
A clear and concise description of what you expected to happen.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Environment (please complete the following information):**
 - OS: [e.g. Ubuntu 22.04, macOS 13.0]
 - Kubernetes Version: [e.g. v1.28.0]
 - MongoDB Version: [e.g. 8.2.1-ent]
 - Deployment Method: [e.g. Single executable, Step-by-step]
 - Browser [e.g. chrome, safari] (if applicable)

**Configuration**
Please share your `deploy.conf` file (remove sensitive information like passwords):
```json
{
  "environment": {
    "os": "ubuntu",
    "k8s_context": "minikube",
    "mongodb_namespace": "mongodb",
    "mongodb_resource_name": "mdb-rs",
    "mongodb_version": "8.2.1-ent"
  }
}
```

**Logs**
Please include relevant logs:
```bash
# Kubernetes logs
kubectl get pods -n mongodb
kubectl logs -n mongodb deployment/mongodb-kubernetes-operator

# MongoDB logs
kubectl logs -n mongodb mdb-rs-0 -c mongodb-enterprise-database

# Search logs
kubectl logs -n mongodb mdb-rs-search-0
```

**Additional Context**
Add any other context about the problem here.

**Possible Solution**
If you have ideas on how to fix this bug, please describe them here.


