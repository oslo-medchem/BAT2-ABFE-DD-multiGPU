#!/bin/bash
################################################################################
# BAT Automation Package - MDIN Fixer
# 
# Applies fixes to mdin files for rest/n* windows ONLY
# Fixes: dt=0.002, ntwprt=0, remove infe=1
################################################################################

# Source dependencies
# Note: config.sh and utils.sh are sourced by main script
# We don't re-source them here to avoid path confusion

################################################################################
# MDIN Fix Functions
################################################################################

needs_fixing() {
    # Check if a window needs fixing (only rest/n* windows)
    local window_path="$1"
    
    # Only fix rest/n* windows
    if echo "$window_path" | grep -q "/rest/n[0-9]"; then
        return 0  # Needs fixing
    else
        return 1  # Does not need fixing
    fi
}

is_already_fixed() {
    # Check if mdin files have already been fixed
    local window_dir="$1"
    
    # Check if backup files exist
    for stage in $MDIN_STAGES; do
        if [ -f "${window_dir}/mdin-${stage}.backup" ]; then
            return 0  # Already fixed
        fi
    done
    
    return 1  # Not yet fixed
}

backup_mdin_file() {
    # Backup an mdin file
    local mdin_file="$1"
    
    if [ ! -f "$mdin_file" ]; then
        log_error "MDIN file not found: $mdin_file"
        return 1
    fi
    
    if [ "$BACKUP_MDIN_FILES" = "1" ]; then
        cp "$mdin_file" "${mdin_file}.backup"
        if [ $? -ne 0 ]; then
            log_error "Failed to backup: $mdin_file"
            return 1
        fi
        log_message "Backed up: $mdin_file" "DEBUG"
    fi
    
    return 0
}

fix_dt_parameter() {
    # Fix dt parameter in mdin file
    # Changes dt = 0.004 to dt = 0.002
    local mdin_file="$1"
    
    if grep -q "dt\s*=" "$mdin_file"; then
        # Get current dt value
        local current_dt=$(grep "dt\s*=" "$mdin_file" | grep -oP 'dt\s*=\s*\K[\d.]+' | head -1)
        
        if [ "$current_dt" != "$N_WINDOW_DT" ]; then
            # Replace dt value
            sed -i "s/dt\s*=\s*[0-9.]*/dt = ${N_WINDOW_DT}/" "$mdin_file"
            log_message "Fixed dt in $(basename $mdin_file): $current_dt -> $N_WINDOW_DT" "DEBUG"
            return 0
        fi
    fi
    
    return 1  # No change needed
}

fix_ntwprt_parameter() {
    # Fix ntwprt parameter in mdin file
    # Changes ntwprt = <any> to ntwprt = 0
    local mdin_file="$1"
    
    if grep -q "ntwprt\s*=" "$mdin_file"; then
        local current_ntwprt=$(grep "ntwprt\s*=" "$mdin_file" | grep -oP 'ntwprt\s*=\s*\K\d+' | head -1)
        
        if [ "$current_ntwprt" != "$N_WINDOW_NTWPRT" ]; then
            sed -i "s/ntwprt\s*=\s*[0-9]*/ntwprt = ${N_WINDOW_NTWPRT}/" "$mdin_file"
            log_message "Fixed ntwprt in $(basename $mdin_file): $current_ntwprt -> $N_WINDOW_NTWPRT" "DEBUG"
            return 0
        fi
    fi
    
    return 1  # No change needed
}

remove_infe_parameter() {
    # Remove infe parameter from mdin file
    local mdin_file="$1"
    
    if [ "$N_WINDOW_REMOVE_INFE" = "1" ]; then
        if grep -q "infe\s*=" "$mdin_file"; then
            sed -i '/infe\s*=/d' "$mdin_file"
            log_message "Removed infe parameter from $(basename $mdin_file)" "DEBUG"
            return 0
        fi
    fi
    
    return 1  # No change needed
}

fix_mdin_file() {
    # Apply all fixes to a single mdin file
    local mdin_file="$1"
    local changes=0
    
    if [ ! -f "$mdin_file" ]; then
        log_error "MDIN file not found: $mdin_file"
        return 1
    fi
    
    # Backup first
    backup_mdin_file "$mdin_file"
    
    # Apply fixes
    if fix_dt_parameter "$mdin_file"; then
        ((changes++))
    fi
    
    if fix_ntwprt_parameter "$mdin_file"; then
        ((changes++))
    fi
    
    if remove_infe_parameter "$mdin_file"; then
        ((changes++))
    fi
    
    return $changes
}

fix_window() {
    # Fix all mdin files in a window directory
    local window_dir="$1"
    local total_changes=0
    
    # Check if already fixed
    if is_already_fixed "$window_dir"; then
        log_message "Window already fixed: $window_dir" "DEBUG"
        return 0
    fi
    
    # Fix each mdin stage
    for stage in $MDIN_STAGES; do
        local mdin_file="${window_dir}/mdin-${stage}"
        
        if [ -f "$mdin_file" ]; then
            fix_mdin_file "$mdin_file"
            local changes=$?
            ((total_changes += changes))
        else
            log_warning "MDIN file not found: $mdin_file"
        fi
    done
    
    if [ $total_changes -gt 0 ]; then
        log_message "Fixed $total_changes parameters in $window_dir" "INFO"
    fi
    
    return 0
}

fix_all_n_windows() {
    # Find and fix all rest/n* windows
    local fixed_count=0
    local skipped_count=0
    
    log_message "Scanning for rest/n* windows to fix..." "INFO"
    print_info "Fixing rest/n* windows (dt, ntwprt, infe)..."
    
    # Find all rest/n* directories
    while IFS= read -r -d '' window_dir; do
        if needs_fixing "$window_dir"; then
            if is_already_fixed "$window_dir"; then
                log_message "Already fixed: $window_dir" "DEBUG"
                ((skipped_count++))
            else
                fix_window "$window_dir"
                if [ $? -eq 0 ]; then
                    ((fixed_count++))
                    log_message "Fixed: $window_dir" "INFO"
                else
                    log_error "Failed to fix: $window_dir"
                fi
            fi
        fi
    done < <(find "$BASE_DIR" -type d -name "n[0-9]*" -path "*/rest/*" -print0 2>/dev/null)
    
    print_success "Fixed $fixed_count rest/n* windows (skipped $skipped_count already fixed)"
    log_message "Total fixed: $fixed_count, skipped: $skipped_count" "INFO"
    
    return 0
}

verify_fixes() {
    # Verify that fixes were applied correctly
    local window_dir="$1"
    local errors=0
    
    for stage in $MDIN_STAGES; do
        local mdin_file="${window_dir}/mdin-${stage}"
        
        if [ ! -f "$mdin_file" ]; then
            continue
        fi
        
        # Check dt
        local dt=$(grep "dt\s*=" "$mdin_file" | grep -oP 'dt\s*=\s*\K[\d.]+' | head -1)
        if [ "$dt" != "$N_WINDOW_DT" ]; then
            log_error "dt not fixed in $mdin_file: expected $N_WINDOW_DT, got $dt"
            ((errors++))
        fi
        
        # Check ntwprt
        local ntwprt=$(grep "ntwprt\s*=" "$mdin_file" | grep -oP 'ntwprt\s*=\s*\K\d+' | head -1)
        if [ "$ntwprt" != "$N_WINDOW_NTWPRT" ]; then
            log_error "ntwprt not fixed in $mdin_file: expected $N_WINDOW_NTWPRT, got $ntwprt"
            ((errors++))
        fi
        
        # Check infe removed
        if [ "$N_WINDOW_REMOVE_INFE" = "1" ]; then
            if grep -q "infe\s*=" "$mdin_file"; then
                log_error "infe not removed from $mdin_file"
                ((errors++))
            fi
        fi
    done
    
    return $errors
}

restore_from_backup() {
    # Restore mdin files from backup
    local window_dir="$1"
    local restored=0
    
    for stage in $MDIN_STAGES; do
        local mdin_file="${window_dir}/mdin-${stage}"
        local backup_file="${mdin_file}.backup"
        
        if [ -f "$backup_file" ]; then
            cp "$backup_file" "$mdin_file"
            if [ $? -eq 0 ]; then
                ((restored++))
                log_message "Restored: $mdin_file" "INFO"
            else
                log_error "Failed to restore: $mdin_file"
            fi
        fi
    done
    
    return $restored
}

################################################################################
# Statistics Functions
################################################################################

get_fix_statistics() {
    # Get statistics on fixed windows
    local total_n_windows=0
    local fixed_windows=0
    
    while IFS= read -r -d '' window_dir; do
        ((total_n_windows++))
        if is_already_fixed "$window_dir"; then
            ((fixed_windows++))
        fi
    done < <(find "$BASE_DIR" -type d -name "n[0-9]*" -path "*/rest/*" -print0 2>/dev/null)
    
    echo "$fixed_windows $total_n_windows"
}

################################################################################
# Export Functions
################################################################################

export -f needs_fixing is_already_fixed backup_mdin_file
export -f fix_dt_parameter fix_ntwprt_parameter remove_infe_parameter
export -f fix_mdin_file fix_window fix_all_n_windows
export -f verify_fixes restore_from_backup get_fix_statistics
