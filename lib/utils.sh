#!/bin/bash
################################################################################
# BAT Automation Package - Utility Functions
# 
# Common utility functions used throughout the package
################################################################################

# Source configuration if not already loaded
if [ -z "$USE_COLORS" ]; then
    # Find config.sh relative to this script
    LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${LIB_DIR}/../config.sh" 2>/dev/null || true
fi

################################################################################
# Color Definitions
################################################################################

if [ "$USE_COLORS" = "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[0;37m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    WHITE=''
    BOLD=''
    NC=''
fi

################################################################################
# Logging Functions
################################################################################

setup_logging() {
    # Validate BASE_DIR is set
    if [ -z "$BASE_DIR" ]; then
        echo "ERROR: BASE_DIR not set before setup_logging"
        exit 1
    fi
    
    # Create log directory if it doesn't exist
    local log_path="${BASE_DIR}/${LOG_DIR}"
    
    # Ensure we're not trying to create at root
    if [ "$log_path" = "/logs" ] || [ "$log_path" = "/${LOG_DIR}" ]; then
        echo "ERROR: Invalid log path: $log_path"
        echo "BASE_DIR appears to be empty or '/'"
        echo "BASE_DIR: '$BASE_DIR'"
        exit 1
    fi
    
    mkdir -p "$log_path" 2>/dev/null || {
        echo "ERROR: Cannot create log directory: $log_path"
        echo "Please check permissions and BASE_DIR setting"
        echo "BASE_DIR: $BASE_DIR"
        exit 1
    }
    
    # Initialize log files
    touch "${log_path}/${MAIN_LOG}" || {
        echo "ERROR: Cannot create log file: ${log_path}/${MAIN_LOG}"
        exit 1
    }
    touch "${log_path}/${ERROR_LOG}" || {
        echo "ERROR: Cannot create error log file: ${log_path}/${ERROR_LOG}"
        exit 1
    }
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========================================" >> "${log_path}/${MAIN_LOG}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] BAT Automation Started" >> "${log_path}/${MAIN_LOG}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] BASE_DIR: $BASE_DIR" >> "${log_path}/${MAIN_LOG}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========================================" >> "${log_path}/${MAIN_LOG}"
}

log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local log_path="${BASE_DIR}/${LOG_DIR}/${MAIN_LOG}"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$log_path"
    
    if [ "$VERBOSE" = "1" ] || [ "$level" = "ERROR" ]; then
        echo "[$(date '+%H:%M:%S')] $message"
    fi
}

log_error() {
    local message="$1"
    local error_path="${BASE_DIR}/${LOG_DIR}/${ERROR_LOG}"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message" >> "$error_path"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message" >> "${BASE_DIR}/${LOG_DIR}/${MAIN_LOG}"
    print_error "$message"
}

################################################################################
# Print Functions (with colors)
################################################################################

print_header() {
    echo -e "${BLUE}${BOLD}========================================${NC}"
    echo -e "${BLUE}${BOLD}$1${NC}"
    echo -e "${BLUE}${BOLD}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

################################################################################
# Validation Functions
################################################################################

validate_directory() {
    local dir="$1"
    local name="$2"
    
    if [ ! -d "$dir" ]; then
        log_error "$name directory not found: $dir"
        return 1
    fi
    return 0
}

validate_file() {
    local file="$1"
    local name="$2"
    
    if [ ! -f "$file" ]; then
        log_error "$name file not found: $file"
        return 1
    fi
    return 0
}

validate_executable() {
    local cmd="$1"
    local name="$2"
    
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$name not found in PATH: $cmd"
        return 1
    fi
    return 0
}

################################################################################
# Environment Detection
################################################################################

detect_num_gpus() {
    if [ -z "$NUM_GPUS" ]; then
        NUM_GPUS=$(nvidia-smi -L 2>/dev/null | wc -l)
        if [ "$NUM_GPUS" -eq 0 ]; then
            log_error "No GPUs detected!"
            return 1
        fi
    fi
    export NUM_GPUS
    log_message "Detected $NUM_GPUS GPUs" "INFO"
    return 0
}

detect_pmemd_cuda() {
    if [ -z "$PMEMD_CUDA" ]; then
        PMEMD_CUDA=$(command -v pmemd.cuda 2>/dev/null)
        if [ -z "$PMEMD_CUDA" ]; then
            log_error "pmemd.cuda not found in PATH!"
            return 1
        fi
    fi
    
    if [ ! -x "$PMEMD_CUDA" ]; then
        log_error "pmemd.cuda is not executable: $PMEMD_CUDA"
        return 1
    fi
    
    export PMEMD_CUDA
    log_message "Found pmemd.cuda: $PMEMD_CUDA" "INFO"
    return 0
}

detect_base_dir() {
    # If BASE_DIR already set and valid, use it
    if [ -n "$BASE_DIR" ] && [ -d "$BASE_DIR" ]; then
        log_message "Using provided BASE_DIR: $BASE_DIR" "INFO"
        export BASE_DIR
        return 0
    fi
    
    # Otherwise detect from current directory
    if [ -z "$BASE_DIR" ]; then
        BASE_DIR="$(pwd)"
    fi
    
    # If we're in fe/, use it directly
    if [ "$(basename "$BASE_DIR")" = "fe" ]; then
        export BASE_DIR
        log_message "Base directory: $BASE_DIR" "INFO"
        return 0
    fi
    
    # If fe/ exists as subdirectory, use it
    if [ -d "$BASE_DIR/fe" ]; then
        BASE_DIR="$BASE_DIR/fe"
        export BASE_DIR
        log_message "Base directory: $BASE_DIR" "INFO"
        return 0
    fi
    
    # Neither condition met
    log_error "Not in fe/ directory and fe/ subdirectory not found"
    log_error "Current directory: $(pwd)"
    return 1
}

################################################################################
# Setup Functions
################################################################################

setup_tracking_dir() {
    # Validate BASE_DIR is set
    if [ -z "$BASE_DIR" ]; then
        echo "ERROR: BASE_DIR not set before setup_tracking_dir"
        exit 1
    fi
    
    local tracking_path="${BASE_DIR}/${TRACKING_DIR}"
    
    # Ensure we're not trying to create at root
    if [ "$tracking_path" = "/.automation_tracking" ] || [ "$tracking_path" = "/${TRACKING_DIR}" ]; then
        echo "ERROR: Invalid tracking path: $tracking_path"
        echo "BASE_DIR appears to be empty or '/'"
        exit 1
    fi
    
    # Create tracking directory
    mkdir -p "$tracking_path" || {
        log_error "Cannot create tracking directory: $tracking_path"
        return 1
    }
    
    # Initialize tracking files
    touch "${tracking_path}/${JOB_QUEUE_FILE}"
    touch "${tracking_path}/${ACTIVE_JOBS_FILE}"
    touch "${tracking_path}/${COMPLETED_JOBS_FILE}"
    touch "${tracking_path}/${FAILED_JOBS_FILE}"
    
    log_message "Tracking directory initialized: $tracking_path" "INFO"
}

cleanup_tracking_files() {
    local tracking_path="${BASE_DIR}/${TRACKING_DIR}"
    
    if [ "$CLEANUP_ON_COMPLETION" = "1" ]; then
        log_message "Cleaning up tracking files" "INFO"
        rm -rf "$tracking_path"
    else
        log_message "Tracking files preserved in: $tracking_path" "INFO"
    fi
}

################################################################################
# Preservation Functions
################################################################################

preserve_environment() {
    # Capture current environment for background jobs
    export ORIGINAL_PATH="$PATH"
    export ORIGINAL_LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
    
    log_message "Environment preserved for background jobs" "DEBUG"
}

################################################################################
# Permission Functions
################################################################################

fix_all_permissions() {
    local fixed_count=0
    local start_time=$(date +%s)
    
    log_message "Fixing permissions on run-local.bash files..." "INFO"
    print_info "Fixing permissions on run-local.bash files..."
    
    # Find all run-local.bash files and make them executable
    # Use a more efficient approach with explicit error handling
    local file_list=$(find "$BASE_DIR" -type f -name "run-local.bash" 2>/dev/null)
    
    if [ -z "$file_list" ]; then
        log_message "No run-local.bash files found" "WARN"
        print_warning "No run-local.bash files found in $BASE_DIR"
        return 0
    fi
    
    local total_files=$(echo "$file_list" | wc -l)
    log_message "Found $total_files run-local.bash files" "INFO"
    
    while IFS= read -r file; do
        if [ ! -x "$file" ]; then
            chmod +x "$file" 2>/dev/null
            if [ $? -eq 0 ]; then
                ((fixed_count++))
                log_message "Fixed: $file" "DEBUG"
            else
                log_warning "Failed to fix permissions: $file"
            fi
        fi
    done <<< "$file_list"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_message "Fixed permissions on $fixed_count/$total_files files in ${duration}s" "INFO"
    print_success "Fixed permissions on $fixed_count files (${duration}s)"
}

################################################################################
# Helper Functions
################################################################################

get_ligand_name() {
    # Extract ligand name from path
    # e.g., /path/to/fe/lig-abc/rest/m00 -> lig-abc
    local path="$1"
    echo "$path" | grep -oP 'lig-[^/]+' | head -1
}

get_window_type() {
    # Extract window type from path
    # e.g., /path/to/fe/lig-abc/rest/m00 -> m
    local path="$1"
    basename "$path" | grep -oP '^[a-z]'
}

get_window_number() {
    # Extract window number from path
    # e.g., /path/to/fe/lig-abc/rest/m00 -> 00
    local path="$1"
    basename "$path" | grep -oP '\d+$'
}

get_component() {
    # Determine if window is in rest or dd
    local path="$1"
    if echo "$path" | grep -q "/rest/"; then
        echo "rest"
    elif echo "$path" | grep -q "/dd/"; then
        echo "dd"
    else
        echo "unknown"
    fi
}

################################################################################
# Signal Handling
################################################################################

setup_signal_handlers() {
    trap 'handle_interrupt' INT TERM
}

handle_interrupt() {
    echo ""
    print_warning "Interrupt received. Cleaning up..."
    log_message "User interrupt received" "WARN"
    
    # Note: Running jobs will continue
    print_info "Running jobs will continue in background"
    print_info "Use 'pkill pmemd.cuda' to stop all running jobs"
    
    exit 130
}

################################################################################
# Timestamp Functions
################################################################################

get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

get_short_timestamp() {
    date '+%H:%M:%S'
}

################################################################################
# Export Functions
################################################################################

export -f log_message log_error
export -f print_header print_success print_error print_warning print_info
export -f validate_directory validate_file validate_executable
export -f detect_num_gpus detect_pmemd_cuda detect_base_dir
export -f setup_tracking_dir cleanup_tracking_files
export -f preserve_environment fix_all_permissions
export -f get_ligand_name get_window_type get_window_number get_component
export -f get_timestamp get_short_timestamp
