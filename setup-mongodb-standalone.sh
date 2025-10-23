#!/bin/bash
set -e

# MongoDB Enterprise Standalone Setup Script
# This script sets up MongoDB Enterprise with authentication and replica set
# in a clean, sequential manner that avoids permission issues

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║    MongoDB Enterprise Standalone Setup                      ║"
echo "║    Clean deployment with proper auth & replica set          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Configuration
MONGODB_VERSION="8.2.1-ubuntu2204"
ADMIN_PASSWORD="${MONGODB_ADMIN_PASSWORD:-password123}"
CONTAINER_NAME="mongodb-enterprise"
VOLUME_NAME="mongodb-data"
KEYFILE_DIR="mongo-setup"

# Clean up existing container and volume
log_info "Cleaning up existing resources..."
docker rm -f ${CONTAINER_NAME} 2>/dev/null || true
docker volume rm ${VOLUME_NAME} 2>/dev/null || true
rm -rf ${KEYFILE_DIR} 2>/dev/null || true

log_success "Cleanup complete"

# Create setup directory
log_info "Creating setup directory..."
mkdir -p ${KEYFILE_DIR}

# Generate keyfile
log_info "Generating keyfile..."
openssl rand -base64 756 > ${KEYFILE_DIR}/keyfile
chmod 600 ${KEYFILE_DIR}/keyfile

log_success "Keyfile generated"

# Create mongod config file
log_info "Creating MongoDB configuration..."
cat > ${KEYFILE_DIR}/mongod.conf << 'EOF'
security:
  authorization: enabled
  keyFile: /data/db/keyfile
replication:
  replSetName: rs0
net:
  bindIp: 0.0.0.0
  port: 27017
storage:
  dbPath: /data/db
systemLog:
  destination: file
  path: /data/db/mongod.log
  logAppend: true
EOF

log_success "Configuration created"

# Create volume and setup keyfile with correct permissions
log_info "Setting up Docker volume..."
docker volume create ${VOLUME_NAME}

log_info "Copying keyfile to volume with correct permissions..."
docker run --rm \
  -v ${VOLUME_NAME}:/data/db \
  -v $(pwd)/${KEYFILE_DIR}:/setup \
  alpine:latest \
  sh -c 'cp /setup/keyfile /data/db/keyfile && chmod 400 /data/db/keyfile && chown -R 999:999 /data/db && ls -la /data/db'

log_success "Volume and keyfile configured"

# Start MongoDB Enterprise
log_info "Starting MongoDB Enterprise ${MONGODB_VERSION}..."
docker run -d \
  --name ${CONTAINER_NAME} \
  -p 27017:27017 \
  -v ${VOLUME_NAME}:/data/db \
  -v $(pwd)/${KEYFILE_DIR}/mongod.conf:/etc/mongod.conf \
  mongodb/mongodb-enterprise-server:${MONGODB_VERSION} \
  mongod --config /etc/mongod.conf

log_info "Waiting for MongoDB to start (15 seconds)..."
sleep 15

# Check if MongoDB is running
if ! docker ps | grep -q ${CONTAINER_NAME}; then
    log_error "MongoDB failed to start!"
    log_info "Checking logs..."
    docker logs ${CONTAINER_NAME}
    exit 1
fi

log_success "MongoDB is running"

# Create admin user (uses localhost exception - no auth needed for local connections before replica set init)
log_info "Creating admin user..."
docker exec ${CONTAINER_NAME} mongosh --eval "
use admin
db.createUser({
  user: 'admin',
  pwd: '${ADMIN_PASSWORD}',
  roles: [{role: 'root', db: 'admin'}]
})
print('✅ Admin user created successfully!')
" || {
    log_error "Failed to create admin user"
    docker logs ${CONTAINER_NAME} | tail -20
    exit 1
}

log_success "Admin user created"

# Initialize replica set
log_info "Initializing replica set..."
docker exec ${CONTAINER_NAME} mongosh -u admin -p "${ADMIN_PASSWORD}" \
  --authenticationDatabase admin --eval "
rs.initiate({
  _id: 'rs0',
  members: [{_id: 0, host: 'localhost:27017'}]
})
print('✅ Replica set initialized!')
" || {
    log_error "Failed to initialize replica set"
    exit 1
}

log_info "Waiting for replica set to stabilize (10 seconds)..."
sleep 10

# Create search database
log_info "Creating search database..."
docker exec ${CONTAINER_NAME} mongosh -u admin -p "${ADMIN_PASSWORD}" \
  --authenticationDatabase admin --eval "
use searchdb
db.createCollection('documents')
print('✅ Search database created!')
"

log_success "Search database ready"

# Verify setup
log_info "Verifying setup..."
docker exec ${CONTAINER_NAME} mongosh -u admin -p "${ADMIN_PASSWORD}" \
  --authenticationDatabase admin --eval "
print('Replica Set Status:')
printjson(rs.status().members[0])
print('')
print('Databases:')
printjson(db.adminCommand('listDatabases'))
"

echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║    ✅ MongoDB Enterprise Setup Complete!                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "📊 Deployment Summary:"
echo "   Container: ${CONTAINER_NAME}"
echo "   Port: 27017"
echo "   Replica Set: rs0"
echo "   Admin User: admin"
echo "   Admin Password: ${ADMIN_PASSWORD}"
echo ""
echo "🔗 Connection String:"
echo "   mongodb://admin:${ADMIN_PASSWORD}@localhost:27017/searchdb?replicaSet=rs0&authSource=admin"
echo ""
echo "📋 Useful Commands:"
echo "   # Connect to MongoDB shell"
echo "   docker exec -it ${CONTAINER_NAME} mongosh -u admin -p ${ADMIN_PASSWORD} --authenticationDatabase admin"
echo ""
echo "   # View logs"
echo "   docker logs -f ${CONTAINER_NAME}"
echo ""
echo "   # Stop MongoDB"
echo "   docker stop ${CONTAINER_NAME}"
echo ""
echo "   # Start MongoDB (after stopping)"
echo "   docker start ${CONTAINER_NAME}"
echo ""
echo "   # Clean up everything"
echo "   docker rm -f ${CONTAINER_NAME} && docker volume rm ${VOLUME_NAME}"
echo ""
echo "🎯 Next Steps:"
echo "   1. Update docker-compose.yml to use external MongoDB (optional)"
echo "   2. Or start backend/frontend containers separately"
echo "   3. Deploy Kubernetes search nodes: ./deploy-search-only.sh"
echo ""

