#!/bin/bash
#
# Install Linux Agent Cron Job
#
# This script sets up a cron job to run the system metrics agent at regular intervals.
# Default: Every 5 minutes
#
# Usage:
#   ./install_cron.sh                    # Install with defaults (every 5 minutes)
#   ./install_cron.sh --interval 10      # Run every 10 minutes
#   ./install_cron.sh --remove           # Remove the cron job
#   ./install_cron.sh --dry-run          # Show what would be installed
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_SCRIPT="${SCRIPT_DIR}/post_system_metrics.py"
CRON_TAG="# linux_agent_metrics"
DEFAULT_INTERVAL=5
LOG_FILE="/var/log/linux_agent_metrics.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
Linux Agent Cron Job Installer

Usage: $0 [OPTIONS]

Options:
    -i, --interval MINUTES   Set cron interval in minutes (default: 5)
    -r, --remove             Remove the existing cron job
    -d, --dry-run            Show what would be installed without making changes
    -q, --quiet              Run in quiet mode for cron execution
    -h, --help               Show this help message

Examples:
    $0                       Install with default 5-minute interval
    $0 --interval 10         Run every 10 minutes
    $0 --interval 1          Run every minute
    $0 --remove              Remove the cron job
    $0 --dry-run             Preview cron job without installing

Additional Agent Options (passed to post_system_metrics.py):
    --api-url URL           Override the API endpoint
    --project-name NAME     Set project name (default: Workstations)
    --system-name NAME      Set system name (default: Monitoring)
    --threshold-warning N   Set warning threshold (default: 85)
    --threshold-error N     Set error threshold (default: 95)
    --check-stopped         Also check for stopped enabled services

Environment Variables:
    AGENT_API_URL           Override API URL via environment
    AGENT_PROJECT_NAME      Override project name via environment
    AGENT_SYSTEM_NAME       Override system name via environment
EOF
}

INTERVAL=$DEFAULT_INTERVAL
REMOVE=false
DRY_RUN=false
EXTRA_ARGS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interval)
            INTERVAL="$2"
            shift 2
            ;;
        -r|--remove)
            REMOVE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -q|--quiet)
            EXTRA_ARGS="${EXTRA_ARGS} --quiet"
            shift
            ;;
        --api-url)
            EXTRA_ARGS="${EXTRA_ARGS} --api-url $2"
            shift 2
            ;;
        --project-name)
            EXTRA_ARGS="${EXTRA_ARGS} --project-name $2"
            shift 2
            ;;
        --system-name)
            EXTRA_ARGS="${EXTRA_ARGS} --system-name $2"
            shift 2
            ;;
        --threshold-warning)
            EXTRA_ARGS="${EXTRA_ARGS} --threshold-warning $2"
            shift 2
            ;;
        --threshold-error)
            EXTRA_ARGS="${EXTRA_ARGS} --threshold-error $2"
            shift 2
            ;;
        --check-stopped)
            EXTRA_ARGS="${EXTRA_ARGS} --check-stopped"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if the agent script exists
if [[ ! -f "$AGENT_SCRIPT" ]]; then
    print_error "Agent script not found: $AGENT_SCRIPT"
    exit 1
fi

# Check for Python 3 and get full path for cron
PYTHON_CMD=""
if command -v python3 &> /dev/null; then
    PYTHON_CMD="$(which python3)"
elif command -v python &> /dev/null; then
    PYTHON_VERSION=$(python --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1)
    if [[ "$PYTHON_VERSION" == "3" ]]; then
        PYTHON_CMD="$(which python)"
    fi
fi

if [[ -z "$PYTHON_CMD" ]]; then
    print_error "Python 3 is required but not found"
    exit 1
fi

print_info "Using Python: ${PYTHON_CMD}"

# Build the cron command
CRON_CMD="${PYTHON_CMD} ${AGENT_SCRIPT}${EXTRA_ARGS} >> ${LOG_FILE} 2>&1"

# Build the cron entry
CRON_ENTRY="*/${INTERVAL} * * * * ${CRON_CMD} ${CRON_TAG}"

# Function to remove existing cron job
remove_cron() {
    print_info "Removing existing Linux Agent cron job..."
    
    # Get current crontab, filter out our job
    (crontab -l 2>/dev/null || true) | grep -v "${CRON_TAG}" | crontab -
    
    print_success "Cron job removed"
}

# Function to install cron job
install_cron() {
    print_info "Installing Linux Agent cron job..."
    print_info "Interval: Every ${INTERVAL} minutes"
    print_info "Command: ${CRON_CMD}"
    
    # Remove existing job first
    (crontab -l 2>/dev/null || true) | grep -v "${CRON_TAG}" | crontab -
    
    # Add new job
    (crontab -l 2>/dev/null || true; echo "${CRON_ENTRY}") | crontab -
    
    print_success "Cron job installed"
    
    # Show current crontab
    print_info "Current crontab:"
    crontab -l | grep -v "^#" | head -20
}

# Main logic
if $DRY_RUN; then
    print_info "[DRY RUN] Would install the following cron entry:"
    echo ""
    echo "  ${CRON_ENTRY}"
    echo ""
    print_info "Log file: ${LOG_FILE}"
elif $REMOVE; then
    remove_cron
else
    # Make the script executable
    chmod +x "$AGENT_SCRIPT"
    chmod +x "${SCRIPT_DIR}/get_system_metrics.py"
    
    install_cron
    
    print_info ""
    print_info "Next steps:"
    print_info "  1. Test manually: ${PYTHON_CMD} ${AGENT_SCRIPT}"
    print_info "  2. Check logs: tail -f ${LOG_FILE}"
    print_info "  3. Verify cron: crontab -l"
fi
