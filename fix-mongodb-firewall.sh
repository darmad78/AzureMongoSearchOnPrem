#!/bin/bash
# Script to open MongoDB port on VM
# Run this ON THE VM (not locally)

echo "=== Opening MongoDB Port 27017 ==="
echo ""

# 1. Open UFW firewall (Ubuntu/Debian)
if command -v ufw &> /dev/null; then
    echo "1. Opening port 27017 in UFW..."
    sudo ufw allow 27017/tcp
    sudo ufw reload
    echo "✅ UFW: Port 27017 opened"
    echo ""
fi

# 2. Check if port is listening
echo "2. Verifying MongoDB is listening on port 27017..."
if sudo netstat -tlnp | grep 27017 || sudo ss -tlnp | grep 27017; then
    echo "✅ MongoDB is listening on port 27017"
else
    echo "❌ MongoDB is NOT listening on port 27017"
    echo "   Check if MongoDB container is running: docker ps | grep mongodb"
fi

echo ""
echo "=== Azure Network Security Group (NSG) ==="
echo "⚠️  IMPORTANT: You also need to open port 27017 in Azure NSG!"
echo ""
echo "Steps:"
echo "1. Go to Azure Portal"
echo "2. Find your VM → Networking"
echo "3. Add inbound port rule:"
echo "   - Port: 27017"
echo "   - Protocol: TCP"
echo "   - Source: Your IP or Any"
echo "   - Action: Allow"
echo ""
echo "After opening NSG, test connection from your local machine:"
echo "  mongosh 'mongodb://admin:password123@136.112.200.116:27017/searchdb?authSource=admin'"

