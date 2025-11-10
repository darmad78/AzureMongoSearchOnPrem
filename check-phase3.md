# Phase 3 Verification Checklist

After running Phase 3 (MongoDB Search deployment), verify the following:

## 1. Check MongoDBSearch CR Status
```bash
kubectl get mongodbsearch mdb-rs -n mongodb
# OR if different CRD:
kubectl get mdbs mdb-rs -n mongodb

# Should show: PHASE=Running
```

## 2. Check mongot Pods
```bash
kubectl get pods -n mongodb | grep search
# Should show: mdb-rs-search-0 (or similar) in Running state, Ready 1/1
```

## 3. Check All Pods Status
```bash
kubectl get pods -n mongodb
# Should show:
# - mdb-rs-0, mdb-rs-1, mdb-rs-2 (all Running, Ready 1/1)
# - mdb-rs-search-0 (Running, Ready 1/1)
```

## 4. Check MongoDB Enterprise Still Running
```bash
kubectl get mdb mdb-rs -n mongodb
# Should show: PHASE=Running
```

## 5. Check Operator Logs for Errors
```bash
kubectl logs -n mongodb deploy/mongodb-kubernetes-operator --tail=50
# Look for:
# - No error messages
# - Successful reconcile messages for MongoDBSearch
# - mongot process started successfully
```

## 6. Check Search Sync User
```bash
kubectl get mongodbuser search-sync-source-user -n mongodb
# Should exist and be in Ready state
```

## 7. Check Secrets
```bash
kubectl get secrets -n mongodb | grep -E "search|sync"
# Should show:
# - mdb-rs-search-sync-source-password
# - mdb-rs-search-keyfile
```

## 8. Check mongot Pod Logs
```bash
kubectl logs -n mongodb -l app=mongodb-rs-search-svc --tail=50
# OR if you know the pod name:
kubectl logs -n mongodb mdb-rs-search-0 --tail=50
# Look for:
# - No error messages
# - mongot started successfully
# - Connected to MongoDB
```

## 9. Describe MongoDBSearch Resource
```bash
kubectl describe mongodbsearch mdb-rs -n mongodb
# OR:
kubectl describe mdbs mdb-rs -n mongodb
# Look for:
# - Phase: Running
# - No error conditions
# - Events showing successful deployment
```

## 10. Test mongot Connection (Optional)
```bash
# Get mongot pod name
MONGOT_POD=$(kubectl get pods -n mongodb -l app=mongodb-rs-search-svc -o jsonpath='{.items[0].metadata.name}')

# Check if mongot is responding
kubectl exec -n mongodb ${MONGOT_POD} -- curl -s http://localhost:27017 || echo "mongot health check"
```

## Common Issues and Fixes

### Issue: MongoDBSearch stuck in Pending
- **Check**: `kubectl describe mongodbsearch mdb-rs -n mongodb`
- **Possible causes**: 
  - Insufficient resources
  - MongoDB not ready
  - Operator not reconciling

### Issue: mongot pod not starting
- **Check**: `kubectl describe pod mdb-rs-search-0 -n mongodb`
- **Check logs**: `kubectl logs mdb-rs-search-0 -n mongodb`

### Issue: Search sync user not created
- **Check**: `kubectl get mongodbuser -n mongodb`
- **Recreate if needed**: The script should have created it, but verify it exists

## Expected Final State

✅ **MongoDB Enterprise**: 3 pods running (mdb-rs-0, mdb-rs-1, mdb-rs-2)  
✅ **MongoDB Search**: 1 pod running (mdb-rs-search-0)  
✅ **All CRs**: Running phase  
✅ **All Pods**: Ready 1/1  
✅ **Operator**: No errors in logs  

If all checks pass, your MongoDB Search deployment is successful! 🎉

