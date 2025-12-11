#!/bin/bash
# Script to open MongoDB port 27017 on GCP VM
# This can be run from your local machine or from the VM

echo "=== GCP Firewall Rule for MongoDB Port 27017 ==="
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI not found"
    echo ""
    echo "Install gcloud CLI:"
    echo "  https://cloud.google.com/sdk/docs/install"
    echo ""
    echo "Or configure firewall via GCP Console:"
    echo "  1. Go to: https://console.cloud.google.com/compute/firewalls"
    echo "  2. Click 'Create Firewall Rule'"
    echo "  3. Name: allow-mongodb-27017"
    echo "  4. Direction: Ingress"
    echo "  5. Targets: All instances in the network (or specific tags)"
    echo "  6. Source IP ranges: 0.0.0.0/0 (or your IP for security)"
    echo "  7. Protocols and ports: TCP, Port: 27017"
    echo "  8. Click Create"
    exit 1
fi

echo "Creating GCP firewall rule to allow MongoDB port 27017..."
echo ""

# Get current project
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo "❌ No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo "Current GCP Project: $PROJECT_ID"
echo ""

# Get default network (or ask user)
NETWORK=$(gcloud compute networks list --format="value(name)" --filter="name:default" | head -1)
if [ -z "$NETWORK" ]; then
    NETWORK=$(gcloud compute networks list --format="value(name)" | head -1)
fi

if [ -z "$NETWORK" ]; then
    echo "⚠️  Could not detect network. You'll need to specify it."
    read -p "Enter VPC network name: " NETWORK
fi

echo "Using network: $NETWORK"
echo ""

# Create firewall rule
RULE_NAME="allow-mongodb-27017"

echo "Creating firewall rule: $RULE_NAME"
echo ""

gcloud compute firewall-rules create $RULE_NAME \
    --project=$PROJECT_ID \
    --direction=INGRESS \
    --priority=1000 \
    --network=$NETWORK \
    --action=ALLOW \
    --rules=tcp:27017 \
    --source-ranges=0.0.0.0/0 \
    --description="Allow MongoDB connections on port 27017" \
    --target-tags="" 2>&1

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Firewall rule created successfully!"
    echo ""
    echo "⚠️  SECURITY NOTE:"
    echo "   The rule allows connections from ANY IP (0.0.0.0/0)"
    echo "   For better security, restrict to your IP:"
    echo ""
    echo "   gcloud compute firewall-rules update $RULE_NAME \\"
    echo "     --source-ranges=YOUR_IP/32"
    echo ""
    echo "To restrict to your IP, run:"
    echo "  gcloud compute firewall-rules update $RULE_NAME --source-ranges=$(curl -s ifconfig.me)/32"
else
    echo ""
    echo "⚠️  Rule might already exist. Checking existing rules..."
    gcloud compute firewall-rules list --filter="name:$RULE_NAME"
    echo ""
    echo "If rule exists, verify it allows port 27017:"
    echo "  gcloud compute firewall-rules describe $RULE_NAME"
fi

echo ""
echo "=== Next Steps ==="
echo "1. Verify firewall rule:"
echo "   gcloud compute firewall-rules describe $RULE_NAME"
echo ""
echo "2. On the VM, ensure MongoDB is listening:"
echo "   sudo netstat -tlnp | grep 27017"
echo ""
echo "3. On the VM, open local firewall (if UFW is enabled):"
echo "   sudo ufw allow 27017/tcp"
echo ""
echo "4. Test connection from your local machine:"
echo "   mongosh 'mongodb://admin:password123@136.112.200.116:27017/searchdb?authSource=admin'"

