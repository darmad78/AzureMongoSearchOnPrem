# MongoDB Cloud Manager Setup Guide

This guide shows you how to get Cloud Manager credentials for deploying MongoDB Enterprise with the Kubernetes Operator.

## Why Cloud Manager?

- ✅ **Free tier available** - No cost for basic monitoring
- ✅ **No local deployment** - Cloud-hosted management
- ✅ **Official support** - Fully supported by MongoDB
- ✅ **Works with mongot** - Enables MongoDB Search deployment
- ✅ **Easy setup** - Just need API credentials

## Step 1: Create MongoDB Cloud Account

1. Go to [cloud.mongodb.com](https://cloud.mongodb.com/)
2. Click **"Sign Up"** or **"Try Free"**
3. Create account with email
4. Verify your email

## Step 2: Create or Select Organization

1. After login, you'll see the Organizations page
2. Either:
   - Use the default organization created for you
   - Click **"Create New Organization"**
3. **Copy the Organization ID** from the URL or settings
   - Example URL: `https://cloud.mongodb.com/v2/YOUR_ORG_ID#/clusters`

## Step 3: Create a Project

1. Click **"New Project"** or use existing project
2. Give it a name (e.g., "K8s MongoDB")
3. Click **"Create Project"**
4. **Copy the Project ID** from the URL
   - Example: `https://cloud.mongodb.com/v2/ORG_ID#/clusters/detail/PROJECT_ID`

## Step 4: Create API Key

1. In your project, go to **"Project Settings"** (gear icon)
2. Click **"Access Manager"** in left sidebar
3. Click **"API Keys"** tab
4. Click **"Create API Key"**
5. Configure the key:
   - **Description**: `Kubernetes Operator`
   - **Project Permissions**: Select **"Project Owner"**
6. Click **"Next"**
7. **IMPORTANT**: Copy and save these credentials:
   ```
   Public Key:  xxxxxxxxxxxx
   Private Key: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```
   ⚠️ **The private key is shown only once!** Save it now.
8. Add your IP to API Access List (or use `0.0.0.0/0` for testing)
9. Click **"Done"**

## Step 5: Gather All Credentials

You should now have:

```bash
Organization ID:  5f4a1b2c3d4e5f6g7h8i9j0k
Project ID:       1a2b3c4d5e6f7g8h9i0j1k2l
Public API Key:   abcdefgh
Private API Key:  12345678-1234-1234-1234-123456789abc
```

## Step 6: Run the Deployment Script

On your VM:

```bash
cd ~/RAGOnPremMongoDB
git pull origin main

# Option 1: Set environment variables
export CM_ORG_ID="your-org-id"
export CM_PROJECT_ID="your-project-id"
export CM_PUBLIC_KEY="your-public-key"
export CM_PRIVATE_KEY="your-private-key"

./deploy-enterprise-cloud-manager.sh

# Option 2: Let the script prompt you
./deploy-enterprise-cloud-manager.sh
# (It will ask for credentials if not set)
```

## What Happens After Deployment?

1. **In your VM**: MongoDB pods start running in Kubernetes
2. **In Cloud Manager**: You'll see your cluster appear at:
   ```
   https://cloud.mongodb.com/v2/YOUR_ORG_ID#/clusters
   ```
3. You can monitor metrics, logs, and performance from Cloud Manager

## Features Available in Cloud Manager

- 📊 **Real-time Metrics** - CPU, memory, disk, operations/sec
- 📈 **Query Performance** - Slow query analysis
- 🔍 **Index Suggestions** - Automatic index recommendations
- 🚨 **Alerts** - Email/SMS notifications
- 📜 **Audit Logs** - Track all database operations
- 🔄 **Backup** - Automated backup management (paid tier)

## Troubleshooting

### "Invalid API Key"
- Ensure you copied the full private key
- Check that the API key has "Project Owner" permissions
- Verify the Organization ID and Project ID match

### "Access Denied"
- Add your VM's public IP to the API Access List in Cloud Manager
- Or temporarily use `0.0.0.0/0` (not recommended for production)

### "Resource not found"
- Double-check Organization ID and Project ID
- Ensure the project exists in Cloud Manager

## Free Tier Limitations

The free tier includes:
- ✅ Cluster monitoring and metrics
- ✅ Query performance advisor
- ✅ Alert management
- ✅ User management
- ❌ Automated backups (paid feature)
- ❌ Advanced security features (paid)

For this demo/development setup, the free tier is sufficient!

## Security Best Practices

1. **Never commit credentials** to Git
2. **Use environment variables** for sensitive data
3. **Rotate API keys** regularly
4. **Use IP whitelisting** in production
5. **Enable 2FA** on your Cloud Manager account

## Next Steps

After successful deployment:
1. View your cluster in Cloud Manager
2. Explore metrics and monitoring
3. Test MongoDB Search (mongot) functionality
4. Access your application at http://localhost:5173

## Support

- 📚 [Cloud Manager Documentation](https://www.mongodb.com/docs/cloud-manager/)
- 💬 [MongoDB Community Forums](https://www.mongodb.com/community/forums/)
- 📧 [Cloud Manager Support](https://support.mongodb.com/)

