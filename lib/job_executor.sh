#!/bin/bash
################################################################################
# BAT Automation Package - Job Executor
# 
# Executes jobs with proper environment preservation and GPU assignment
################################################################################

# Source dependencies
# Note: config.sh, utils.sh, and gpu_manager.sh are sourced by main script
# We don't re-source them here to avoid path confusion

################################################################################
# Job Execution Functions
################################################################################

execute_window() {
    # Execute run-local.bash for a single window
    # Args: window_path ligand component window_type window_number gpu_id
    
    local window_path="$1"
    local ligand="$2"
    local component="$3"
    local window_type="$4"
    local window_number="$5"
    local gpu_id="$6"
    
    # Validate window directory
    if [ ! -d "$window_path" ]; then
        log_error "Window directory not found: $window_path"
        return 1
    fi
    
    # Validate run-local.bash
    if [ ! -f "${window_path}/run-local.bash" ]; then
        log_error "run-local.bash not found in: $window_path"
        return 1
    fi
    
    # Ensure executable
    if [ ! -x "${window_path}/run-local.bash" ]; then
        chmod +x "${window_path}/run-local.bash" 2>/dev/null
        if [ $? -ne 0 ]; then
            log_error "Cannot make run-local.bash executable: $window_path"
            return 1
        fi
    fi
    
    # Clean up any previous failed runs
    clean_window_outputs "$window_path"
    
    # Launch job in background with environment preservation
    bash -c "
        cd '$window_path' || exit 1
        export PATH='$ORIGINAL_PATH'
        export LD_LIBRARY_PATH='$ORIGINAL_LD_LIBRARY_PATH'
        export CUDA_VISIBLE_DEVICES=$gpu_id
        exec ./run-local.bash > run.log 2>&1
    " &
    
    local job_pid=$!
    
    # Record active job
    add_active_job "$window_path" "$ligand" "$component" "$window_type" "$window_number" "$gpu_id" "$job_pid"
    
    # Log job start
    log_message "Started: $ligand/$component/$window_type$window_number on GPU $gpu_id (PID $job_pid)" "INFO"
    
    # Brief delay to ensure process starts
    sleep $JOB_START_DELAY
    
    # Verify process is running
    if ! kill -0 $job_pid 2>/dev/null; then
        log_error "Job failed to start: $ligand/$component/$window_type$window_number"
        remove_active_job $job_pid
        return 1
    fi
    
    return 0
}

clean_window_outputs() {
    # Clean up output files from previous runs
    local window_dir="$1"
    
    # Remove output files but keep input files
    rm -f "${window_dir}"/md*.out "${window_dir}"/md*.rst7 "${window_dir}"/md*.nc \
          "${window_dir}"/mdinfo "${window_dir}"/mden "${window_dir}"/run.log 2>/dev/null
    
    log_message "Cleaned outputs in: $window_dir" "DEBUG"
}

################################################################################
# Job Queue Management
################################################################################

process_job_queue() {
    # Main loop to process job queue
    # Continuously checks for free GPUs and starts new jobs
    
    local queue_file="${BASE_DIR}/${TRACKING_DIR}/${JOB_QUEUE_FILE}"
    local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
    
    log_message "Starting job queue processing" "INFO"
    print_info "Processing job queue with strict 1-job-per-GPU enforcement"
    echo ""
    
    local jobs_started=0
    
    # Main processing loop
    while [ -s "$queue_file" ] || [ -s "$active_file" ]; do
        # Check for finished jobs
        check_finished_jobs
        local finished=$?
        
        # Get current status
        local active_count=$(count_active_jobs)
        local queue_count=$(wc -l < "$queue_file" 2>/dev/null || echo 0)
        
        # Try to start new jobs if we have capacity
        if [ "$active_count" -lt "$NUM_GPUS" ] && [ "$queue_count" -gt 0 ]; then
            # Get free GPU
            local gpu_id=$(get_free_gpu)
            
            if [ -n "$gpu_id" ]; then
                # Get next job from queue
                local next_job=$(head -1 "$queue_file")
                
                if [ -n "$next_job" ]; then
                    # Remove from queue
                    sed -i '1d' "$queue_file"
                    
                    # Parse job info
                    local window_path=$(echo "$next_job" | cut -d'|' -f1)
                    local ligand=$(echo "$next_job" | cut -d'|' -f2)
                    local component=$(echo "$next_job" | cut -d'|' -f3)
                    local window_type=$(echo "$next_job" | cut -d'|' -f4)
                    local window_number=$(echo "$next_job" | cut -d'|' -f5)
                    
                    # Execute job
                    execute_window "$window_path" "$ligand" "$component" "$window_type" "$window_number" "$gpu_id"
                    
                    if [ $? -eq 0 ]; then
                        ((jobs_started++))
                        
                        # Print status
                        local completed=$(wc -l < "${BASE_DIR}/${TRACKING_DIR}/${COMPLETED_JOBS_FILE}" 2>/dev/null || echo 0)
                        local failed=$(wc -l < "${BASE_DIR}/${TRACKING_DIR}/${FAILED_JOBS_FILE}" 2>/dev/null || echo 0)
                        
                        echo "[$(get_short_timestamp)] Started: $ligand/$component/$window_type$window_number (GPU $gpu_id) | Running: $((active_count + 1))/$NUM_GPUS | Done: $completed | Failed: $failed | Queue: $queue_count"
                    fi
                fi
            fi
        fi
        
        # Wait before next iteration
        sleep $JOB_CHECK_INTERVAL
    done
    
    log_message "Job queue processing completed. Total jobs started: $jobs_started" "INFO"
    print_success "All jobs completed!"
    
    return 0
}

start_next_job() {
    # Start the next available job from queue
    # Returns 0 if job started, 1 if no job available or no free GPU
    
    local queue_file="${BASE_DIR}/${TRACKING_DIR}/${JOB_QUEUE_FILE}"
    
    # Check if queue has jobs
    if [ ! -s "$queue_file" ]; then
        return 1
    fi
    
    # Check if we have capacity
    local active_count=$(count_active_jobs)
    if [ "$active_count" -ge "$NUM_GPUS" ]; then
        return 1
    fi
    
    # Get free GPU
    local gpu_id=$(get_free_gpu)
    if [ -z "$gpu_id" ]; then
        return 1
    fi
    
    # Get next job
    local next_job=$(head -1 "$queue_file")
    if [ -z "$next_job" ]; then
        return 1
    fi
    
    # Remove from queue
    sed -i '1d' "$queue_file"
    
    # Parse and execute
    local window_path=$(echo "$next_job" | cut -d'|' -f1)
    local ligand=$(echo "$next_job" | cut -d'|' -f2)
    local component=$(echo "$next_job" | cut -d'|' -f3)
    local window_type=$(echo "$next_job" | cut -d'|' -f4)
    local window_number=$(echo "$next_job" | cut -d'|' -f5)
    
    execute_window "$window_path" "$ligand" "$component" "$window_type" "$window_number" "$gpu_id"
    
    return $?
}

################################################################################
# Job Control Functions
################################################################################

stop_all_jobs() {
    # Stop all running jobs
    local active_file="${BASE_DIR}/${TRACKING_DIR}/${ACTIVE_JOBS_FILE}"
    
    if [ ! -f "$active_file" ] || [ ! -s "$active_file" ]; then
        print_info "No active jobs to stop"
        return 0
    fi
    
    log_message "Stopping all active jobs" "WARN"
    print_warning "Stopping all active jobs..."
    
    local stopped_count=0
    
    while IFS='|' read -r window_path ligand component window_type window_number gpu_id pid start_time; do
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null
            ((stopped_count++))
            log_message "Stopped job: PID $pid ($ligand/$component/$window_type$window_number)" "INFO"
        fi
    done < "$active_file"
    
    # Clear active jobs file
    : > "$active_file"
    
    print_success "Stopped $stopped_count jobs"
    
    return 0
}

pause_job_queue() {
    # Pause job queue processing (stop starting new jobs)
    local pause_file="${BASE_DIR}/${TRACKING_DIR}/.paused"
    
    touch "$pause_file"
    log_message "Job queue paused" "INFO"
    print_warning "Job queue paused - no new jobs will start"
}

resume_job_queue() {
    # Resume job queue processing
    local pause_file="${BASE_DIR}/${TRACKING_DIR}/.paused"
    
    rm -f "$pause_file"
    log_message "Job queue resumed" "INFO"
    print_success "Job queue resumed"
}

is_queue_paused() {
    # Check if job queue is paused
    local pause_file="${BASE_DIR}/${TRACKING_DIR}/.paused"
    
    if [ -f "$pause_file" ]; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Statistics Functions
################################################################################

get_execution_statistics() {
    # Get statistics on job execution
    
    local completed_file="${BASE_DIR}/${TRACKING_DIR}/${COMPLETED_JOBS_FILE}"
    local failed_file="${BASE_DIR}/${TRACKING_DIR}/${FAILED_JOBS_FILE}"
    
    local total_completed=0
    local total_failed=0
    local total_duration=0
    local min_duration=999999
    local max_duration=0
    
    if [ -f "$completed_file" ]; then
        total_completed=$(wc -l < "$completed_file")
        
        while IFS='|' read -r window_path ligand component window_type window_number gpu_id pid duration status; do
            total_duration=$((total_duration + duration))
            
            if [ "$duration" -lt "$min_duration" ]; then
                min_duration=$duration
            fi
            
            if [ "$duration" -gt "$max_duration" ]; then
                max_duration=$duration
            fi
        done < "$completed_file"
    fi
    
    if [ -f "$failed_file" ]; then
        total_failed=$(wc -l < "$failed_file")
    fi
    
    local avg_duration=0
    if [ "$total_completed" -gt 0 ]; then
        avg_duration=$((total_duration / total_completed))
    fi
    
    echo "$total_completed $total_failed $avg_duration $min_duration $max_duration"
}

################################################################################
# Export Functions
################################################################################

export -f execute_window clean_window_outputs
export -f process_job_queue start_next_job
export -f stop_all_jobs pause_job_queue resume_job_queue is_queue_paused
export -f get_execution_statistics
