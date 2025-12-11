#!/bin/bash
################################################################################
# BAT Automation Package - Window Scanner
# 
# Scans the directory structure and identifies all windows to process
################################################################################

# Source dependencies
# Note: config.sh and utils.sh are sourced by main script
# We don't re-source them here to avoid path confusion

################################################################################
# Window Detection Functions
################################################################################

find_all_ligands() {
    # Find all lig-* directories in BASE_DIR
    local ligands=()
    
    while IFS= read -r -d '' dir; do
        ligands+=("$(basename "$dir")")
    done < <(find "$BASE_DIR" -maxdepth 1 -type d -name "lig-*" -print0 2>/dev/null | sort -z)
    
    echo "${ligands[@]}"
}

find_windows_in_component() {
    # Find all windows in a specific component (rest or dd)
    # Args: ligand_dir component_name window_types
    local ligand_dir="$1"
    local component="$2"
    local window_types="$3"
    
    local windows=()
    local component_dir="${ligand_dir}/${component}"
    
    if [ ! -d "$component_dir" ]; then
        return 0
    fi
    
    # For each window type (m, n, e, v, f, w)
    for type in $window_types; do
        while IFS= read -r -d '' window_dir; do
            # Verify it has required files
            if validate_window_directory "$window_dir"; then
                windows+=("$window_dir")
            fi
        done < <(find "$component_dir" -maxdepth 1 -type d -name "${type}[0-9]*" -print0 2>/dev/null | sort -z)
    done
    
    echo "${windows[@]}"
}

validate_window_directory() {
    # Check if a window directory has all required files
    local window_dir="$1"
    
    # Check for run-local.bash
    if [ ! -f "${window_dir}/run-local.bash" ]; then
        log_message "Missing run-local.bash in $window_dir" "DEBUG"
        return 1
    fi
    
    # Check for required input files
    for file in full.hmr.prmtop full.inpcrd; do
        if [ ! -f "${window_dir}/${file}" ]; then
            log_message "Missing $file in $window_dir" "DEBUG"
            return 1
        fi
    done
    
    # Check for mdin files
    for stage in $MDIN_STAGES; do
        if [ ! -f "${window_dir}/mdin-${stage}" ]; then
            log_message "Missing mdin-${stage} in $window_dir" "DEBUG"
            return 1
        fi
    done
    
    return 0
}

scan_all_windows() {
    # Scan entire directory structure and build job queue
    local total_windows=0
    local ligands=($(find_all_ligands))
    
    if [ ${#ligands[@]} -eq 0 ]; then
        log_error "No lig-* directories found in $BASE_DIR"
        return 1
    fi
    
    log_message "Found ${#ligands[@]} ligands: ${ligands[*]}" "INFO"
    print_info "Scanning ${#ligands[@]} ligands for windows..."
    
    # Statistics
    declare -A window_counts
    window_counts[rest_m]=0
    window_counts[rest_n]=0
    window_counts[dd_e]=0
    window_counts[dd_v]=0
    window_counts[dd_f]=0
    window_counts[dd_w]=0
    
    # For each ligand
    for ligand in "${ligands[@]}"; do
        local ligand_dir="${BASE_DIR}/${ligand}"
        
        if [ ! -d "$ligand_dir" ]; then
            log_warning "Ligand directory not found: $ligand_dir"
            continue
        fi
        
        # Scan rest/ windows
        local rest_windows=($(find_windows_in_component "$ligand_dir" "rest" "$REST_WINDOW_TYPES"))
        for window in "${rest_windows[@]}"; do
            local window_type=$(get_window_type "$window")
            add_window_to_queue "$window" "$ligand" "rest" "$window_type"
            ((window_counts[rest_${window_type}]++))
            ((total_windows++))
        done
        
        # Scan dd/ windows
        local dd_windows=($(find_windows_in_component "$ligand_dir" "dd" "$DD_WINDOW_TYPES"))
        for window in "${dd_windows[@]}"; do
            local window_type=$(get_window_type "$window")
            add_window_to_queue "$window" "$ligand" "dd" "$window_type"
            ((window_counts[dd_${window_type}]++))
            ((total_windows++))
        done
    done
    
    # Print summary
    print_success "Found $total_windows windows to process"
    echo "  Breakdown:"
    echo "    rest/m*: ${window_counts[rest_m]} windows"
    echo "    rest/n*: ${window_counts[rest_n]} windows"
    echo "    dd/e*:   ${window_counts[dd_e]} windows"
    echo "    dd/v*:   ${window_counts[dd_v]} windows"
    echo "    dd/f*:   ${window_counts[dd_f]} windows"
    echo "    dd/w*:   ${window_counts[dd_w]} windows"
    
    log_message "Total windows found: $total_windows" "INFO"
    
    return 0
}

add_window_to_queue() {
    # Add a window to the job queue
    # Format: window_path|ligand|component|window_type|window_number
    local window_path="$1"
    local ligand="$2"
    local component="$3"
    local window_type="$4"
    
    local window_number=$(get_window_number "$window_path")
    local queue_file="${BASE_DIR}/${TRACKING_DIR}/${JOB_QUEUE_FILE}"
    
    echo "${window_path}|${ligand}|${component}|${window_type}|${window_number}" >> "$queue_file"
}

check_window_status() {
    # Check if a window has completed successfully
    local window_dir="$1"
    
    # Check if final output file exists
    if [ ! -f "${window_dir}/${SUCCESS_CHECK_FILE}" ]; then
        return 1
    fi
    
    # Check for success marker
    if grep -q "$SUCCESS_MARKER" "${window_dir}/${SUCCESS_CHECK_FILE}" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

is_window_running() {
    # Check if a window is currently being processed
    local window_path="$1"
    local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
    
    if [ -f "$active_file" ]; then
        if grep -q "^${window_path}|" "$active_file" 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

count_windows_by_status() {
    # Count windows by their status
    local tracking_dir="${BASE_DIR}/${TRACKING_DIR}"
    
    local queued=$(wc -l < "${tracking_dir}/${JOB_QUEUE_FILE}" 2>/dev/null || echo 0)
    local active=$(wc -l < "${tracking_dir}/${ACTIVE_JOBS_FILE}" 2>/dev/null || echo 0)
    local completed=$(wc -l < "${tracking_dir}/${COMPLETED_JOBS_FILE}" 2>/dev/null || echo 0)
    local failed=$(wc -l < "${tracking_dir}/${FAILED_JOBS_FILE}" 2>/dev/null || echo 0)
    
    echo "$queued $active $completed $failed"
}

get_windows_by_ligand() {
    # Get all windows for a specific ligand
    # Args: ligand_name
    local ligand="$1"
    local queue_file="${BASE_DIR}/${TRACKING_DIR}/${JOB_QUEUE_FILE}"
    
    if [ -f "$queue_file" ]; then
        grep "|${ligand}|" "$queue_file" 2>/dev/null || true
    fi
}

get_windows_by_type() {
    # Get all windows of a specific type
    # Args: window_type (m, n, e, v, f, w)
    local type="$1"
    local queue_file="${BASE_DIR}/${TRACKING_DIR}/${JOB_QUEUE_FILE}"
    
    if [ -f "$queue_file" ]; then
        grep "|${type}|" "$queue_file" 2>/dev/null || true
    fi
}

################################################################################
# Export Functions
################################################################################

export -f find_all_ligands find_windows_in_component validate_window_directory
export -f scan_all_windows add_window_to_queue
export -f check_window_status is_window_running count_windows_by_status
export -f get_windows_by_ligand get_windows_by_type
