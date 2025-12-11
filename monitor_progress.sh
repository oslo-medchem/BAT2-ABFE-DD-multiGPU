#!/bin/bash
################################################################################
# BAT Automation Package - Progress Monitor
# 
# Real-time monitoring of automation progress
# Usage: ./monitor_progress.sh [--continuous]
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/gpu_manager.sh"

# Detect base directory
detect_base_dir 2>/dev/null || BASE_DIR="$(pwd)"
if [ -d "$BASE_DIR/fe" ]; then
    BASE_DIR="$BASE_DIR/fe"
fi

CONTINUOUS=false
if [ "$1" = "--continuous" ]; then
    CONTINUOUS=true
fi

show_status() {
    clear
    
    print_header "BAT Automation - Progress Monitor"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Check if tracking directory exists
    local tracking_dir="${BASE_DIR}/${TRACKING_DIR}"
    if [ ! -d "$tracking_dir" ]; then
        print_warning "No active automation session found"
        echo "Run ./run_automation.sh to start"
        return 1
    fi
    
    # Get counts
    local queue_file="${tracking_dir}/${JOB_QUEUE_FILE}"
    local active_file="${tracking_dir}/${ACTIVE_JOBS_FILE}"
    local completed_file="${tracking_dir}/${COMPLETED_JOBS_FILE}"
    local failed_file="${tracking_dir}/${FAILED_JOBS_FILE}"
    
    local queued=$(wc -l < "$queue_file" 2>/dev/null || echo 0)
    local active=$(wc -l < "$active_file" 2>/dev/null || echo 0)
    local completed=$(wc -l < "$completed_file" 2>/dev/null || echo 0)
    local failed=$(wc -l < "$failed_file" 2>/dev/null || echo 0)
    local total=$((queued + active + completed + failed))
    
    # Overall progress
    echo "Overall Progress:"
    echo "----------------"
    echo "  Total windows: $total"
    echo "  ✓ Completed: $completed"
    echo "  ⚠ Failed: $failed"
    echo "  ⏳ Running: $active"
    echo "  ⏸ Queued: $queued"
    
    if [ $total -gt 0 ]; then
        local percent=$(( ((completed + failed) * 100) / total ))
        echo "  Progress: ${percent}%"
    fi
    echo ""
    
    # GPU Status
    echo "GPU Status:"
    echo "----------"
    for gpu_id in $(seq 0 $(( ${NUM_GPUS:-8} - 1 ))); do
        if [ -f "$active_file" ]; then
            local job_line=$(grep "|${gpu_id}|" "$active_file" 2>/dev/null | head -1)
            if [ -n "$job_line" ]; then
                local ligand=$(echo "$job_line" | cut -d'|' -f2)
                local component=$(echo "$job_line" | cut -d'|' -f3)
                local window_type=$(echo "$job_line" | cut -d'|' -f4)
                local window_number=$(echo "$job_line" | cut -d'|' -f5)
                echo "  GPU $gpu_id: $ligand/$component/$window_type$window_number"
            else
                echo "  GPU $gpu_id: [idle]"
            fi
        else
            echo "  GPU $gpu_id: [idle]"
        fi
    done
    echo ""
    
    # Recent completions
    if [ -f "$completed_file" ] && [ -s "$completed_file" ]; then
        echo "Recent Completions (last 5):"
        echo "---------------------------"
        tail -5 "$completed_file" | while IFS='|' read -r path ligand component type num gpu pid dur status; do
            echo "  $ligand/$component/$type$num (${dur}s)"
        done
        echo ""
    fi
    
    # Recent failures
    if [ -f "$failed_file" ] && [ -s "$failed_file" ]; then
        echo "Recent Failures (last 5):"
        echo "------------------------"
        tail -5 "$failed_file" | while IFS='|' read -r path ligand component type num gpu pid dur status; do
            echo "  $ligand/$component/$type$num ($status)"
        done
        echo ""
    fi
    
    if [ "$CONTINUOUS" = "true" ]; then
        echo "Press Ctrl+C to exit"
        echo "Refreshing every 30 seconds..."
    fi
}

if [ "$CONTINUOUS" = "true" ]; then
    while true; do
        show_status
        sleep 30
    done
else
    show_status
fi
