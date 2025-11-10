#!/bin/bash
set -e

# Setup Persistent Port Forwarding for Kubernetes Services
# This creates a systemd service to automatically forward ports on boot

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Setting up persistent port forwarding for Kubernetes services...${NC}"
echo ""

# Get current user
CURRENT_USER=$(whoami)

# Create systemd service file
echo -e "${YELLOW}Creating systemd service file...${NC}"
sudo tee /etc/systemd/system/k8s-port-forward.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Port Forward for Search Frontend and Backend
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=/home/${CURRENT_USER}
Environment="KUBECONFIG=/home/${CURRENT_USER}/.kube/config"
ExecStartPre=/bin/sleep 30
ExecStart=/bin/bash -c 'kubectl port-forward -n mongodb svc/search-frontend-svc 30173:5173 --address 0.0.0.0 & kubectl port-forward -n mongodb svc/search-backend-svc 30888:8888 --address 0.0.0.0 & wait'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
echo -e "${YELLOW}Reloading systemd daemon...${NC}"
sudo systemctl daemon-reload

# Enable service
echo -e "${YELLOW}Enabling service to start on boot...${NC}"
sudo systemctl enable k8s-port-forward.service

# Start service
echo -e "${YELLOW}Starting service...${NC}"
sudo systemctl start k8s-port-forward.service

# Wait a moment for service to start
sleep 3

# Check status
echo ""
echo -e "${GREEN}✅ Port forwarding service installed!${NC}"
echo ""
echo -e "${BLUE}Service Status:${NC}"
sudo systemctl status k8s-port-forward.service --no-pager -l

echo ""
echo -e "${GREEN}🎉 Setup Complete!${NC}"
echo ""
echo -e "${BLUE}Your services are now accessible at:${NC}"
echo "  Frontend: http://$(curl -s ifconfig.me):30173"
echo "  Backend:  http://$(curl -s ifconfig.me):30888"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  Check status:  sudo systemctl status k8s-port-forward.service"
echo "  Stop service:  sudo systemctl stop k8s-port-forward.service"
echo "  Start service: sudo systemctl start k8s-port-forward.service"
echo "  Restart:       sudo systemctl restart k8s-port-forward.service"
echo "  Disable:       sudo systemctl disable k8s-port-forward.service"
echo "  View logs:     sudo journalctl -u k8s-port-forward.service -f"
echo ""

