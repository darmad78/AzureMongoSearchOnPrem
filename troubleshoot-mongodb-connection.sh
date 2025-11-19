#!/bin/bash
# Troubleshooting script for MongoDB external connection

echo "=== MongoDB Connection Troubleshooting ==="
echo ""

# 1. Check if MongoDB container is running
echo "1. Checking MongoDB container status..."
docker ps | grep mongodb-enterprise || echo "❌ MongoDB container not running!"

# 2. Check if port 27017 is listening
echo ""
echo "2. Checking if port 27017 is listening..."
sudo netstat -tlnp | grep 27017 || sudo ss -tlnp | grep 27017 || echo "❌ Port 27017 not listening!"

# 3. Check firewall status (Ubuntu/Debian)
echo ""
echo "3. Checking firewall status..."
if command -v ufw &> /dev/null; then
    echo "UFW Status:"
    sudo ufw status | grep 27017 || echo "⚠️  Port 27017 not in UFW rules"
    echo ""
    echo "To allow port 27017, run:"
    echo "  sudo ufw allow 27017/tcp"
    echo "  sudo ufw reload"
fi

# 4. Check iptables
echo ""
echo "4. Checking iptables rules..."
sudo iptables -L -n | grep 27017 || echo "⚠️  No iptables rules found for port 27017"

# 5. Test local connection
echo ""
echo "5. Testing local MongoDB connection..."
docker exec mongodb-enterprise mongosh --eval 'db.adminCommand("ping")' --quiet && echo "✅ MongoDB is responding locally" || echo "❌ MongoDB not responding locally"

# 6. Check Docker port mapping
echo ""
echo "6. Checking Docker port mapping..."
docker port mongodb-enterprise 27017 || echo "❌ Port mapping not found"

# 7. Get VM IP addresses
echo ""
echo "7. VM Network Information:"
echo "   Internal IP: $(hostname -I | awk '{print $1}')"
echo "   External IP: $(curl -s ifconfig.me 2>/dev/null || echo 'Unable to determine')"

# 8. Test port from VM itself
echo ""
echo "8. Testing port 27017 from VM..."
timeout 2 bash -c "</dev/tcp/$(hostname -I | awk '{print $1}')/27017" 2>/dev/null && echo "✅ Port 27017 is accessible from VM" || echo "❌ Port 27017 not accessible from VM"

echo ""
echo "=== Next Steps ==="
echo "1. If firewall is blocking, allow port 27017"
echo "2. Check cloud provider security group/NSG rules"
echo "3. Verify MongoDB is bound to 0.0.0.0 (check docker-compose.yml)"
echo "4. Consider using SSH tunnel for secure access"

