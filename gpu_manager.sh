#!/bin/bash
################################################################################
# BAT Automation Package - GPU Manager
# 
# Manages GPU allocation with strict 1-job-per-GPU enforcement
################################################################################

# Source dependencies
# Note: config.sh and utils.sh are sourced by main script
# We don't re-source them here to avoid path confusion

################################################################################
# GPU Tracking Functions
################################################################################

get_free_gpu() {
    # Returns first available GPU ID or empty string if none available
    # Uses active jobs file to track which GPUs are busy
    
    local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
    
    for gpu_id in $(seq 0 $((NUM_GPUS - 1))); do
        # Check if this GPU has any active jobs
        if [ -f "$active_file" ]; then
            if ! grep -q "|${gpu_id}|" "$active_file" 2>/dev/null; then
                # GPU is free
                echo "$gpu_id"
                return 0
            fi
        else
            # No active jobs file means all GPUs are free
            echo "$gpu_id"
            return 0
        fi
    done
    
    # No free GPU
    return 1
}

wait_for_free_gpu() {
    # Wait until at least one GPU becomes free
    # Returns GPU ID when available
    
    local waited=0
    
    while [ $waited -lt $MAX_GPU_WAIT ]; do
        local free_gpu=$(get_free_gpu)
        if [ -n "$free_gpu" ]; then
            echo "$free_gpu"
            return 0
        fi
        
        # Wait before checking again
        sleep $JOB_CHECK_INTERVAL
        waited=$((waited + JOB_CHECK_INTERVAL))
    done
    
    log_error "No GPU became available after ${MAX_GPU_WAIT}s"
    return 1
}

get_gpu_job_count() {
    # Count how many jobs are running on each GPU
    # Returns array of counts
    
    local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
    
    if [ ! -f "$active_file" ]; then
        return 0
    fi
    
    for gpu_id in $(seq 0 $((NUM_GPUS - 1))); do
        local count=$(grep -c "|${gpu_id}|" "$active_file" 2>/dev/null || echo 0)
        echo "GPU${gpu_id}:${count}"
    done
}

verify_gpu_distribution() {
    # Verify that no GPU has more than 1 job
    # Returns 0 if distribution is correct, 1 if any GPU has 2+ jobs
    
    local max_jobs_per_gpu=0
    
    while read -r gpu_info; do
        local count=$(echo "$gpu_info" | cut -d':' -f2)
        if [ "$count" -gt "$max_jobs_per_gpu" ]; then
            max_jobs_per_gpu=$count
        fi
    done < <(get_gpu_job_count)
    
    if [ "$max_jobs_per_gpu" -gt 1 ]; then
        log_error "GPU distribution violated: Max $max_jobs_per_gpu jobs on single GPU"
        return 1
    fi
    
    return 0
}

################################################################################
# Active Job Management
################################################################################

add_active_job() {
    # Add a job to the active jobs list
    # Format: window_path|ligand|component|window_type|window_number|gpu_id|pid|start_time
    local window_path="$1"
    local ligand="$2"
    local component="$3"
    local window_type="$4"
    local window_number="$5"
    local gpu_id="$6"
    local pid="$7"
    
    local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
    local start_time=$(date '+%s')
    
    echo "${window_path}|${ligand}|${component}|${window_type}|${window_number}|${gpu_id}|${pid}|${start_time}" >> "$active_file"
    
    log_message "Added active job: $ligand/$component/$window_type$window_number on GPU $gpu_id (PID $pid)" "DEBUG"
}

remove_active_job() {
    # Remove a job from the active jobs list
    local pid="$1"
    
    local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
    
    if [ -f "$active_file" ]; then
        grep -v "|${pid}|" "$active_file" > "${active_file}.tmp" 2>/dev/null
        mv "${active_file}.tmp" "$active_file"
        log_message "Removed active job with PID $pid" "DEBUG"
    fi
}

get_job_by_pid() {
    # Get job information by PID
    local pid="$1"
    local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
    
    if [ -f "$active_file" ]; then
        grep "|${pid}|" "$active_file" 2>/dev/null | head -1
    fi
}

count_active_jobs() {
    # Count number of active jobs
    local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
    
    if [ -f "$active_file" ]; then
        wc -l < "$active_file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

################################################################################
# Job Status Checking
################################################################################

check_finished_jobs() {
    # Check all active jobs and process any that have finished
    # Returns number of jobs that finished
    
    local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
    local completed_file="${BASE_DIR}/${TRACKING_DIR}/${COMPLETED_JOBS_FILE}"
    local failed_file="${BASE_DIR}/${TRACKING_DIR}/${FAILED_JOBS_FILE}"
    
    local finished_count=0
    
    if [ ! -f "$active_file" ] || [ ! -s "$active_file" ]; then
        return 0
    fi
    
    # Create temporary file for still-active jobs
    local temp_active="${active_file}.checking"
    : > "$temp_active"
    
    while IFS='|' read -r window_path ligand component window_type window_number gpu_id pid start_time; do
        # Check if process is still running
        if kill -0 "$pid" 2>/dev/null; then
            # Still running, keep in active list
            echo "${window_path}|${ligand}|${component}|${window_type}|${window_number}|${gpu_id}|${pid}|${start_time}" >> "$temp_active"
        else
            # Process finished
            ((finished_count++))
            
            local end_time=$(date '+%s')
            local duration=$((end_time - start_time))
            
            # Check if successful
            if [ -f "${window_path}/${SUCCESS_CHECK_FILE}" ]; then
                if grep -q "$SUCCESS_MARKER" "${window_path}/${SUCCESS_CHECK_FILE}" 2>/dev/null; then
                    # Success
                    echo "${window_path}|${ligand}|${component}|${window_type}|${window_number}|${gpu_id}|${pid}|${duration}|SUCCESS" >> "$completed_file"
                    log_message "Job completed: $ligand/$component/$window_type$window_number (${duration}s)" "INFO"
                else
                    # Incomplete
                    echo "${window_path}|${ligand}|${component}|${window_type}|${window_number}|${gpu_id}|${pid}|${duration}|INCOMPLETE" >> "$failed_file"
                    log_message "Job incomplete: $ligand/$component/$window_type$window_number" "WARN"
                fi
            else
                # Failed (no output file)
                echo "${window_path}|${ligand}|${component}|${window_type}|${window_number}|${gpu_id}|${pid}|${duration}|FAILED" >> "$failed_file"
                log_error "Job failed: $ligand/$component/$window_type$window_number"
            fi
        fi
    done < "$active_file"
    
    # Replace active file with updated list
    mv "$temp_active" "$active_file"
    
    return $finished_count
}

################################################################################
# GPU Status Display
################################################################################

show_gpu_status() {
    # Display current GPU usage
    
    echo ""
    echo "GPU Status:"
    echo "----------"
    
    for gpu_id in $(seq 0 $((NUM_GPUS - 1))); do
        local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
        local count=0
        local job_info=""
        
        if [ -f "$active_file" ]; then
            count=$(grep -c "|${gpu_id}|" "$active_file" 2>/dev/null || echo 0)
            
            if [ "$count" -gt 0 ]; then
                # Get job info
                job_info=$(grep "|${gpu_id}|" "$active_file" | head -1)
                local ligand=$(echo "$job_info" | cut -d'|' -f2)
                local component=$(echo "$job_info" | cut -d'|' -f3)
                local window_type=$(echo "$job_info" | cut -d'|' -f4)
                local window_number=$(echo "$job_info" | cut -d'|' -f5)
                
                echo "  GPU $gpu_id: $ligand/$component/$window_type$window_number"
            else
                echo "  GPU $gpu_id: [idle]"
            fi
        else
            echo "  GPU $gpu_id: [idle]"
        fi
    done
    
    echo ""
}

################################################################################
# Validation Functions
################################################################################

validate_gpu_setup() {
    # Validate GPU configuration
    
    # Check if GPUs are available
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "nvidia-smi not found - GPU monitoring unavailable"
        return 1
    fi
    
    # Detect number of GPUs if not set
    if [ -z "$NUM_GPUS" ] || [ "$NUM_GPUS" -eq 0 ]; then
        NUM_GPUS=$(nvidia-smi -L 2>/dev/null | wc -l)
        if [ "$NUM_GPUS" -eq 0 ]; then
            log_error "No GPUs detected"
            return 1
        fi
        export NUM_GPUS
    fi
    
    log_message "GPU setup validated: $NUM_GPUS GPUs available" "INFO"
    return 0
}

################################################################################
# Export Functions
################################################################################

export -f get_free_gpu wait_for_free_gpu get_gpu_job_count verify_gpu_distribution
export -f add_active_job remove_active_job get_job_by_pid count_active_jobs
export -f check_finished_jobs show_gpu_status validate_gpu_setup
