#!/bin/bash
################################################################################
# BAT Automation Package - Main Orchestrator
# 
# Comprehensive automation for running DD simulations across all ligands
# 
# Usage: ./run_automation.sh [OPTIONS]
#
# Options:
#   --fix-only          Only fix n* windows, don't run simulations
#   --run-only          Skip fixing, only run simulations
#   --ligands "lig1 lig2"  Process only specific ligands
#   --skip-validation   Skip pre-flight validation checks
#   --help              Show this help message
################################################################################

set -euo pipefail

# Get script directory (where this script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all modules
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/window_scanner.sh"
source "${SCRIPT_DIR}/lib/mdin_fixer.sh"
source "${SCRIPT_DIR}/lib/gpu_manager.sh"
source "${SCRIPT_DIR}/lib/job_executor.sh"

################################################################################
# Command Line Parsing
################################################################################

FIX_WINDOWS=true
RUN_SIMULATIONS=true
SPECIFIC_LIGANDS=""
SKIP_VALIDATION=false
SKIP_PERMISSION_FIX=false

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --fix-only)
                RUN_SIMULATIONS=false
                shift
                ;;
            --run-only)
                FIX_WINDOWS=false
                shift
                ;;
            --ligands)
                SPECIFIC_LIGANDS="$2"
                shift 2
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --skip-permission-fix)
                SKIP_PERMISSION_FIX=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
BAT Automation Package - Comprehensive DD Simulation Automation

Usage: $0 [OPTIONS]

Options:
  --fix-only          Only fix rest/n* windows (dt, ntwprt, infe), don't run simulations
  --run-only          Skip fixing phase, only run simulations (assumes already fixed)
  --ligands "lig1 lig2 ..."  Process only specific ligands (space-separated)
  --skip-validation   Skip pre-flight validation checks (not recommended)
  --skip-permission-fix  Skip automatic permission fixing (if hanging, use quick_fix_permissions.sh first)
  --help              Show this help message

Examples:
  # Full run (fix + run all ligands)
  $0

  # Only fix n* windows
  $0 --fix-only

  # Only run simulations (if already fixed)
  $0 --run-only

  # Process specific ligands
  $0 --ligands "lig-fmm lig-afp lig-dac"

  # Fix only for specific ligands
  $0 --fix-only --ligands "lig-fmm lig-afp"

Description:
  This script automates the entire DD simulation workflow:
  1. Scans for all ligands under fe/ directory
  2. Finds all windows (rest/m*, rest/n*, dd/e*, dd/v*, dd/f*, dd/w*)
  3. Applies fixes to rest/n* windows (dt=0.002, ntwprt=0, remove infe)
  4. Executes all windows with strict 1-job-per-GPU enforcement
  5. Tracks progress and handles failures

Features:
  - Automatic ligand detection
  - Strict 1-job-per-GPU (prevents memory errors)
  - Dynamic GPU allocation
  - Environment preservation for background jobs
  - Automatic permission fixing
  - Real-time progress tracking
  - Comprehensive logging
  - Failure recovery support

Configuration:
  Edit config.sh to customize settings (GPU count, paths, fix parameters, etc.)

Monitoring:
  Use monitor_progress.sh to watch real-time progress
  Use check_status.sh for quick status check

For more information, see README.md
EOF
}

################################################################################
# Validation Functions
################################################################################

validate_environment() {
    # Pre-flight checks
    
    print_header "Validating Environment"
    
    # BASE_DIR should already be set by main()
    if [ -z "$BASE_DIR" ]; then
        print_error "BASE_DIR not initialized"
        return 1
    fi
    
    # Verify BASE_DIR exists
    if [ ! -d "$BASE_DIR" ]; then
        print_error "BASE_DIR does not exist: $BASE_DIR"
        return 1
    fi
    print_success "Base directory: $BASE_DIR"
    
    # Detect and validate GPUs
    if ! detect_num_gpus; then
        return 1
    fi
    print_success "Found $NUM_GPUS GPUs"
    
    # Detect and validate pmemd.cuda
    if ! detect_pmemd_cuda; then
        return 1
    fi
    print_success "Found pmemd.cuda: $PMEMD_CUDA"
    
    # Validate GPU setup
    if ! validate_gpu_setup; then
        return 1
    fi
    
    echo ""
    return 0
}

validate_structure() {
    # Validate directory structure
    
    print_info "Validating directory structure..."
    
    # Check for ligands
    local ligands=($(find_all_ligands))
    
    if [ ${#ligands[@]} -eq 0 ]; then
        print_error "No lig-* directories found in $BASE_DIR"
        return 1
    fi
    
    print_success "Found ${#ligands[@]} ligands"
    
    # Validate each ligand has rest/ and/or dd/ directories
    local valid_ligands=0
    for ligand in "${ligands[@]}"; do
        if [ -d "${BASE_DIR}/${ligand}/rest" ] || [ -d "${BASE_DIR}/${ligand}/dd" ]; then
            ((valid_ligands++))
        else
            print_warning "Ligand $ligand has no rest/ or dd/ directory"
        fi
    done
    
    if [ $valid_ligands -eq 0 ]; then
        print_error "No valid ligand structures found"
        return 1
    fi
    
    print_success "$valid_ligands valid ligand structures"
    echo ""
    return 0
}

################################################################################
# Main Workflow Functions
################################################################################

phase_1_fixing() {
    # Phase 1: Fix rest/n* windows
    
    print_header "PHASE 1: Fixing rest/n* Windows"
    
    echo "Applying fixes to rest/n* windows:"
    echo "  - dt: 0.004 → $N_WINDOW_DT"
    echo "  - ntwprt: any → $N_WINDOW_NTWPRT"
    if [ "$N_WINDOW_REMOVE_INFE" = "1" ]; then
        echo "  - Remove infe parameter"
    fi
    echo ""
    
    print_info "Starting n* window fixing process..."
    
    # Run the fixer
    if ! fix_all_n_windows; then
        log_error "Failed to fix n* windows"
        return 1
    fi
    
    # Show statistics
    local stats=($(get_fix_statistics))
    local fixed=${stats[0]:-0}
    local total=${stats[1]:-0}
    
    echo ""
    print_success "Phase 1 complete: $fixed/$total rest/n* windows fixed"
    echo ""
    
    return 0
}

phase_2_scanning() {
    # Phase 2: Scan and queue all windows
    
    print_header "PHASE 2: Scanning Windows"
    
    # Filter by specific ligands if requested
    if [ -n "$SPECIFIC_LIGANDS" ]; then
        print_info "Limiting to ligands: $SPECIFIC_LIGANDS"
        
        # Temporarily modify find_all_ligands to filter
        local temp_base="$BASE_DIR"
        BASE_DIR="$BASE_DIR/tmp_filter"
        mkdir -p "$BASE_DIR"
        
        for ligand in $SPECIFIC_LIGANDS; do
            if [ -d "$temp_base/$ligand" ]; then
                ln -s "$temp_base/$ligand" "$BASE_DIR/$ligand" 2>/dev/null
            else
                print_warning "Ligand not found: $ligand"
            fi
        done
        
        # Scan
        scan_all_windows
        local scan_result=$?
        
        # Restore
        rm -rf "$BASE_DIR"
        BASE_DIR="$temp_base"
        
        return $scan_result
    else
        # Scan all ligands
        scan_all_windows
        return $?
    fi
}

phase_3_execution() {
    # Phase 3: Execute all jobs
    
    print_header "PHASE 3: Running Simulations"
    
    echo "Execution strategy:"
    echo "  - Strict 1-job-per-GPU enforcement"
    echo "  - Dynamic GPU allocation"
    echo "  - $NUM_GPUS parallel jobs maximum"
    echo "  - Environment preservation enabled"
    echo ""
    
    # Process the job queue
    process_job_queue
    
    return $?
}

################################################################################
# Cleanup and Summary
################################################################################

show_final_summary() {
    # Show final statistics and summary
    
    print_header "Execution Summary"
    
    # Get statistics
    local stats=($(get_execution_statistics))
    local completed=${stats[0]}
    local failed=${stats[1]}
    local avg_time=${stats[2]}
    local min_time=${stats[3]}
    local max_time=${stats[4]}
    
    local total=$((completed + failed))
    local success_rate=0
    if [ $total -gt 0 ]; then
        success_rate=$(( (completed * 100) / total ))
    fi
    
    echo "Total windows processed: $total"
    echo "  ✓ Completed: $completed"
    echo "  ✗ Failed: $failed"
    echo "  Success rate: ${success_rate}%"
    echo ""
    
    if [ $completed -gt 0 ]; then
        echo "Execution times:"
        echo "  Average: $((avg_time / 60)) min $((avg_time % 60)) sec"
        echo "  Fastest: $((min_time / 60)) min $((min_time % 60)) sec"
        echo "  Slowest: $((max_time / 60)) min $((max_time % 60)) sec"
        echo ""
    fi
    
    # Show log locations
    echo "Logs saved to:"
    echo "  Main log: ${BASE_DIR}/${LOG_DIR}/${MAIN_LOG}"
    echo "  Error log: ${BASE_DIR}/${LOG_DIR}/${ERROR_LOG}"
    echo ""
    
    # Show tracking directory
    echo "Tracking files:"
    echo "  ${BASE_DIR}/${TRACKING_DIR}/"
    echo ""
    
    if [ $failed -gt 0 ]; then
        print_warning "$failed windows failed"
        echo "Use cleanup_failures.sh to analyze and restart failed windows"
        echo ""
    fi
}

################################################################################
# Main Function
################################################################################

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Initialize BASE_DIR FIRST (before any logging or directory creation)
    if [ -z "$BASE_DIR" ]; then
        BASE_DIR="$(pwd)"
    fi
    
    # If we're in fe/ directory, use it; otherwise look for fe/ subdirectory
    if [ "$(basename "$BASE_DIR")" = "fe" ]; then
        # Already in fe/ - good
        export BASE_DIR
    elif [ -d "$BASE_DIR/fe" ]; then
        # Found fe/ subdirectory - use it
        BASE_DIR="$BASE_DIR/fe"
        export BASE_DIR
    else
        # Not in fe/ and no fe/ subdirectory found
        echo "ERROR: Not in fe/ directory and fe/ subdirectory not found"
        echo "Current directory: $(pwd)"
        echo "Please run from BAT root directory (parent of fe/) or from fe/ itself"
        exit 1
    fi
    
    # Print banner
    print_header "BAT Automation Package"
    echo "Comprehensive DD Simulation Automation"
    echo ""
    echo "Started: $(get_timestamp)"
    echo "Working directory: $BASE_DIR"
    echo ""
    
    # Setup (BASE_DIR is now set)
    setup_logging
    setup_signal_handlers
    preserve_environment
    
    # Validation
    if [ "$SKIP_VALIDATION" = "false" ]; then
        if ! validate_environment; then
            print_error "Environment validation failed"
            exit 1
        fi
        
        if ! validate_structure; then
            print_error "Structure validation failed"
            exit 1
        fi
    fi
    
    # Setup tracking
    setup_tracking_dir
    
    # Fix permissions on all run-local.bash files
    if [ "$SKIP_PERMISSION_FIX" = "false" ]; then
        fix_all_permissions
    else
        print_warning "Skipping permission fix as requested"
        print_info "Make sure run-local.bash files are executable!"
        echo ""
    fi
    
    # Phase 1: Fix n* windows
    if [ "$FIX_WINDOWS" = "true" ]; then
        if ! phase_1_fixing; then
            print_error "Phase 1 (fixing) failed"
            exit 1
        fi
    else
        print_info "Skipping Phase 1 (fixing) as requested"
        echo ""
    fi
    
    # Phase 2: Scan and queue windows
    if [ "$RUN_SIMULATIONS" = "true" ]; then
        if ! phase_2_scanning; then
            print_error "Phase 2 (scanning) failed"
            exit 1
        fi
        
        # Phase 3: Execute jobs
        if ! phase_3_execution; then
            print_error "Phase 3 (execution) failed"
            exit 1
        fi
        
        # Show summary
        show_final_summary
    else
        print_info "Skipping simulation execution as requested"
        echo ""
    fi
    
    # Cleanup
    if [ "$CLEANUP_ON_COMPLETION" = "1" ]; then
        cleanup_tracking_files
    fi
    
    # Done
    echo "Completed: $(get_timestamp)"
    print_success "Automation complete!"
    
    return 0
}

################################################################################
# Entry Point
################################################################################

# Run main function with all arguments
main "$@"
exit $?
