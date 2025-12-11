#!/bin/bash

# System Requirements Checker for MongoDB Enterprise Demo
# Checks hardware, software, and network requirements before deployment

# Don't use set -e because we want to continue checking even if some checks fail
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Deployment mode
DEPLOYMENT_MODE="${1:-docker}"  # docker or kubernetes

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((CHECKS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((CHECKS_WARNING++))
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    ((CHECKS_FAILED++))
}

log_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🔍 $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check CPU cores
check_cpu() {
    log_section "Checking CPU Resources"
    
    local cpu_cores
    if [[ "$OSTYPE" == "darwin"* ]]; then
        cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "0")
    elif [[ "$OSTYPE" == "linux"* ]]; then
        cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "0")
    else
        cpu_cores="0"
    fi
    
    local min_cpu
    if [ "$DEPLOYMENT_MODE" = "kubernetes" ]; then
        min_cpu=10
    else
        min_cpu=4
    fi
    
    local recommended_cpu
    if [ "$DEPLOYMENT_MODE" = "kubernetes" ]; then
        recommended_cpu=16
    else
        recommended_cpu=8
    fi
    
    log_info "Detected CPU cores: $cpu_cores"
    log_info "Minimum required: $min_cpu cores"
    log_info "Recommended: $recommended_cpu cores"
    
    if [ "$cpu_cores" -ge "$recommended_cpu" ]; then
        log_success "CPU cores: $cpu_cores (Excellent)"
    elif [ "$cpu_cores" -ge "$min_cpu" ]; then
        log_warning "CPU cores: $cpu_cores (Acceptable, but may be slow)"
        log_warning "Consider upgrading to $recommended_cpu cores for better performance"
    else
        log_error "CPU cores: $cpu_cores (Insufficient - need at least $min_cpu)"
        log_error "Demo will be very slow or may not work properly"
    fi
}

# Check RAM
check_memory() {
    log_section "Checking RAM Resources"
    
    local total_ram_mb
    if [[ "$OSTYPE" == "darwin"* ]]; then
        total_ram_mb=$(($(sysctl -n hw.memsize 2>/dev/null || echo "0") / 1024 / 1024))
    elif [[ "$OSTYPE" == "linux"* ]]; then
        total_ram_mb=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo "0")
    else
        total_ram_mb="0"
    fi
    
    local total_ram_gb=$((total_ram_mb / 1024))
    
    local min_ram
    if [ "$DEPLOYMENT_MODE" = "kubernetes" ]; then
        min_ram=16
    else
        min_ram=8
    fi
    
    local recommended_ram
    if [ "$DEPLOYMENT_MODE" = "kubernetes" ]; then
        recommended_ram=32
    else
        recommended_ram=16
    fi
    
    log_info "Detected RAM: ${total_ram_gb}GB (${total_ram_mb}MB)"
    log_info "Minimum required: ${min_ram}GB"
    log_info "Recommended: ${recommended_ram}GB"
    
    if [ "$total_ram_gb" -ge "$recommended_ram" ]; then
        log_success "RAM: ${total_ram_gb}GB (Excellent)"
    elif [ "$total_ram_gb" -ge "$min_ram" ]; then
        log_warning "RAM: ${total_ram_gb}GB (Acceptable, may experience slowdowns)"
        log_warning "Consider upgrading to ${recommended_ram}GB for better performance"
    else
        log_error "RAM: ${total_ram_gb}GB (Insufficient - need at least ${min_ram}GB)"
        log_error "Demo may fail or be extremely slow"
        log_info "Consider using smaller models (phi instead of llama2)"
    fi
}

# Check disk space
check_disk() {
    log_section "Checking Disk Space"
    
    local free_space_mb
    if [[ "$OSTYPE" == "darwin"* ]]; then
        free_space_mb=$(df -m . 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    elif [[ "$OSTYPE" == "linux"* ]]; then
        free_space_mb=$(df -m . 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    else
        free_space_mb="0"
    fi
    
    local free_space_gb=$((free_space_mb / 1024))
    
    local min_disk
    if [ "$DEPLOYMENT_MODE" = "kubernetes" ]; then
        min_disk=50
    else
        min_disk=10
    fi
    
    local recommended_disk
    if [ "$DEPLOYMENT_MODE" = "kubernetes" ]; then
        recommended_disk=100
    else
        recommended_disk=20
    fi
    
    log_info "Free disk space: ${free_space_gb}GB"
    log_info "Minimum required: ${min_disk}GB"
    log_info "Recommended: ${recommended_disk}GB"
    
    if [ "$free_space_gb" -ge "$recommended_disk" ]; then
        log_success "Disk space: ${free_space_gb}GB (Excellent)"
    elif [ "$free_space_gb" -ge "$min_disk" ]; then
        log_warning "Disk space: ${free_space_gb}GB (Acceptable)"
        log_warning "May need to clean up space after model downloads"
    else
        log_error "Disk space: ${free_space_gb}GB (Insufficient - need at least ${min_disk}GB)"
        log_error "Free up space before deployment"
        log_info "Run: docker system prune -a (to clean Docker cache)"
    fi
}

# Check Docker
check_docker() {
    log_section "Checking Docker"
    
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        log_success "Docker installed: $docker_version"
        
        # Check if Docker is running
        if docker info &> /dev/null; then
            log_success "Docker daemon is running"
            
            # Check Docker resources
            if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux"* ]]; then
                log_info "Docker is operational"
            fi
        else
            log_error "Docker daemon is not running"
            log_info "Start Docker Desktop or run: sudo systemctl start docker"
        fi
    else
        log_error "Docker is not installed"
        log_info "Install from: https://docs.docker.com/get-docker/"
    fi
}

# Check Docker Compose
check_docker_compose() {
    if [ "$DEPLOYMENT_MODE" = "docker" ]; then
        log_section "Checking Docker Compose"
        
        if command -v docker-compose &> /dev/null; then
            local compose_version=$(docker-compose --version 2>/dev/null | awk '{print $4}' | tr -d ',')
            log_success "Docker Compose installed: $compose_version"
        elif docker compose version &> /dev/null; then
            local compose_version=$(docker compose version --short 2>/dev/null)
            log_success "Docker Compose (plugin) installed: $compose_version"
        else
            log_error "Docker Compose is not installed"
            log_info "Install from: https://docs.docker.com/compose/install/"
        fi
    fi
}

# Check Kubernetes tools
check_kubernetes() {
    if [ "$DEPLOYMENT_MODE" = "kubernetes" ]; then
        log_section "Checking Kubernetes Tools"
        
        # Check kubectl
        if command -v kubectl &> /dev/null; then
            local kubectl_version=$(kubectl version --client --short 2>/dev/null | awk '{print $3}' || echo "unknown")
            log_success "kubectl installed: $kubectl_version"
            
            # Check cluster connection
            if kubectl cluster-info &> /dev/null; then
                local cluster_name=$(kubectl config current-context 2>/dev/null)
                log_success "Connected to Kubernetes cluster: $cluster_name"
            else
                log_warning "kubectl installed but no cluster connection"
                log_info "Ensure your Kubernetes cluster is running and configured"
            fi
        else
            log_error "kubectl is not installed"
            log_info "Install from: https://kubernetes.io/docs/tasks/tools/"
        fi
        
        # Check helm
        if command -v helm &> /dev/null; then
            local helm_version=$(helm version --short 2>/dev/null | awk '{print $1}')
            log_success "Helm installed: $helm_version"
        else
            log_error "Helm is not installed"
            log_info "Install from: https://helm.sh/docs/intro/install/"
        fi
    fi
}

# Check network connectivity
check_network() {
    log_section "Checking Network Connectivity"
    
    # Check internet connectivity
    if curl -s --connect-timeout 5 https://www.google.com > /dev/null 2>&1; then
        log_success "Internet connectivity available"
    else
        log_error "No internet connectivity"
        log_info "Internet required to download Docker images and models"
    fi
    
    # Check Docker Hub access
    if curl -s --connect-timeout 5 https://hub.docker.com > /dev/null 2>&1; then
        log_success "Docker Hub accessible"
    else
        log_warning "Cannot reach Docker Hub"
        log_info "May have issues pulling Docker images"
    fi
}

# Check ports availability
check_ports() {
    log_section "Checking Port Availability"
    
    local ports_to_check
    if [ "$DEPLOYMENT_MODE" = "docker" ]; then
        ports_to_check="27017 8000 5173 11434"
    else
        ports_to_check="27017 8080"  # NodePort/LoadBalancer will be assigned
    fi
    
    for port in $ports_to_check; do
        if command -v lsof &> /dev/null; then
            if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
                log_warning "Port $port is already in use"
                log_info "Stop the service using this port or change the port in configuration"
            else
                log_success "Port $port is available"
            fi
        elif command -v netstat &> /dev/null; then
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                log_warning "Port $port may be in use"
            else
                log_success "Port $port is available"
            fi
        else
            log_info "Port $port - Unable to check (lsof/netstat not available)"
        fi
    done
}

# Check OS compatibility
check_os() {
    log_section "Checking Operating System"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
        log_success "macOS detected: $os_version"
        
        # Check if Apple Silicon
        if [[ $(uname -m) == "arm64" ]]; then
            log_info "Apple Silicon (M1/M2) detected"
            log_warning "Some Docker images may require Rosetta 2"
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            local os_name=$(grep ^NAME= /etc/os-release | cut -d'"' -f2)
            local os_version=$(grep ^VERSION= /etc/os-release | cut -d'"' -f2 || echo "")
            log_success "Linux detected: $os_name $os_version"
        else
            log_success "Linux detected"
        fi
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        log_warning "Windows detected"
        log_info "Ensure you're using WSL2 for best compatibility"
    else
        log_warning "Unknown OS: $OSTYPE"
        log_info "Proceed with caution - may have compatibility issues"
    fi
}

# Display summary
show_summary() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📊 Requirements Check Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Deployment Mode: ${BLUE}$DEPLOYMENT_MODE${NC}"
    echo ""
    echo -e "${GREEN}✅ Checks Passed:  $CHECKS_PASSED${NC}"
    echo -e "${YELLOW}⚠️  Warnings:       $CHECKS_WARNING${NC}"
    echo -e "${RED}❌ Checks Failed:  $CHECKS_FAILED${NC}"
    echo ""
    
    if [ $CHECKS_FAILED -eq 0 ] && [ $CHECKS_WARNING -eq 0 ]; then
        echo -e "${GREEN}🎉 All requirements met! Ready to deploy.${NC}"
        echo ""
        echo "Next steps:"
        if [ "$DEPLOYMENT_MODE" = "docker" ]; then
            echo "  docker-compose up -d"
        else
            echo "  ./deploy-phase1-ops-manager.sh"
            echo "  ./deploy-phase2-mongodb-enterprise.sh"
            echo "  ./deploy-phase3-mongodb-search.sh"
            echo "  ./deploy-phase4-ai-models.sh"
            echo "  ./deploy-phase5-backend-frontend.sh"
            echo "  ./verify-and-setup.sh"
        fi
        return 0
    elif [ $CHECKS_FAILED -eq 0 ]; then
        echo -e "${YELLOW}⚠️  Requirements met with warnings.${NC}"
        echo -e "${YELLOW}You can proceed, but may experience issues.${NC}"
        echo ""
        echo "Consider addressing warnings for better performance."
        return 0
    else
        echo -e "${RED}❌ Critical requirements not met.${NC}"
        echo -e "${RED}Please fix the errors above before deploying.${NC}"
        echo ""
        echo "Common fixes:"
        echo "  - Upgrade hardware or use cloud deployment"
        echo "  - Free up disk space: docker system prune -a"
        echo "  - Install missing software"
        echo "  - Start Docker daemon"
        return 1
    fi
}

# Display help
show_help() {
    echo "System Requirements Checker for MongoDB Enterprise Demo"
    echo ""
    echo "Usage: $0 [MODE]"
    echo ""
    echo "Modes:"
    echo "  docker      Check requirements for Docker Compose deployment (default)"
    echo "  kubernetes  Check requirements for Kubernetes deployment"
    echo ""
    echo "Examples:"
    echo "  $0                  # Check Docker requirements"
    echo "  $0 docker           # Check Docker requirements"
    echo "  $0 kubernetes       # Check Kubernetes requirements"
    echo ""
}

# Main function
main() {
    # Show header
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       System Requirements Checker                            ║"
    echo "║       MongoDB Enterprise Advanced Demo                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Validate deployment mode
    if [ "$DEPLOYMENT_MODE" != "docker" ] && [ "$DEPLOYMENT_MODE" != "kubernetes" ]; then
        if [ "$DEPLOYMENT_MODE" = "--help" ] || [ "$DEPLOYMENT_MODE" = "-h" ]; then
            show_help
            exit 0
        fi
        echo -e "${RED}Invalid deployment mode: $DEPLOYMENT_MODE${NC}"
        echo "Use 'docker' or 'kubernetes'"
        echo ""
        show_help
        exit 1
    fi
    
    log_info "Checking requirements for: ${BLUE}$DEPLOYMENT_MODE${NC} deployment"
    
    # Run all checks
    check_os
    check_cpu
    check_memory
    check_disk
    check_docker
    check_docker_compose
    check_kubernetes
    check_network
    check_ports
    
    # Show summary and exit with appropriate code
    show_summary
    exit $?
}

# Run main function
main "$@"

