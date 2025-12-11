#!/bin/bash
set -e

# MongoDB Enterprise Complete Installation Script with Search Fixes
# Includes: Ops Manager setup, MongoDB Enterprise, Search, Backend, Frontend, Ollama
# Handles: Compatibility checks, API key setup, network configuration, Search authentication fixes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "\n${BLUE}🚀 $1${NC}\n=================================================="; }

echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║        MongoDB Enterprise Complete Installation              ║
║    Ops Manager + MongoDB + Search + Backend + Frontend      ║
║              WITH SEARCH AUTHENTICATION FIXES               ║
╚══════════════════════════════════════════════════════════════╝
