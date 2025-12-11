#!/bin/bash
################################################################################
# BAT Automation Package - Configuration File
# 
# This file contains all configurable settings.
# Modify these values to match your system setup.
################################################################################

# GPU Configuration
# -----------------
# Number of GPUs to use (auto-detected if left empty)
NUM_GPUS=""

# Maximum time to wait for a free GPU (in seconds)
# Default: 3600 (1 hour)
MAX_GPU_WAIT=3600

# Delay between job starts (in seconds)
# Helps ensure processes fully initialize before next job starts
JOB_START_DELAY=2

# Job checking interval (in seconds)
# How often to check for finished jobs and start new ones
JOB_CHECK_INTERVAL=5

# AMBER Configuration
# -------------------
# Path to AMBER installation (auto-detected if empty)
AMBERHOME="${AMBERHOME:-}"

# Path to pmemd.cuda (auto-detected if empty)
PMEMD_CUDA=""

# Working Directory Configuration
# --------------------------------
# Base directory containing fe/ folder
# Leave empty to use current directory
BASE_DIR=""

# Window Type Configuration
# --------------------------
# Window types to process in rest/ directory
REST_WINDOW_TYPES="m n"

# Window types to process in dd/ directory
DD_WINDOW_TYPES="e v f w"

# N* Window Fix Configuration
# ----------------------------
# These fixes are applied ONLY to rest/n* windows
# Do NOT apply to m*, e*, v*, f*, w* windows

# Time step for n* windows (original: 0.004)
N_WINDOW_DT="0.002"

# Number of atoms to write trajectory (0 = none, safer for GPU)
N_WINDOW_NTWPRT="0"

# Remove infe flag (set to 1 to remove, 0 to keep)
N_WINDOW_REMOVE_INFE=1

# Backup original mdin files before fixing (1=yes, 0=no)
BACKUP_MDIN_FILES=1

# Logging Configuration
# ----------------------
# Log directory (relative to BASE_DIR or absolute path)
LOG_DIR="logs"

# Log file names
MAIN_LOG="automation.log"
ERROR_LOG="errors.log"

# Enable verbose logging (1=yes, 0=no)
VERBOSE=1

# Job Tracking Configuration
# ---------------------------
# Directory for temporary tracking files
TRACKING_DIR=".automation_tracking"

# File names for tracking
JOB_QUEUE_FILE="job_queue.txt"
ACTIVE_JOBS_FILE="active_jobs.txt"
COMPLETED_JOBS_FILE="completed_jobs.txt"
FAILED_JOBS_FILE="failed_jobs.txt"

# Success Criteria
# ----------------
# String to search for in output files to determine success
SUCCESS_MARKER="Final Performance"

# Output file to check (md-02.out is the final stage)
SUCCESS_CHECK_FILE="md-02.out"

# Color Output
# ------------
# Enable colored terminal output (1=yes, 0=no)
USE_COLORS=1

# Performance Settings
# --------------------
# Maximum number of retries for failed windows
MAX_RETRIES=1

# Cleanup temporary files on completion (1=yes, 0=no)
CLEANUP_ON_COMPLETION=0

################################################################################
# Advanced Settings (Usually don't need to change)
################################################################################

# MDIN file stages
MDIN_STAGES="00 01 02"

# Required files in each window directory
REQUIRED_FILES="full.hmr.prmtop full.inpcrd mdin-00 mdin-01 mdin-02"

# Output files to check for completion
OUTPUT_FILES="md-00.out md-01.out md-02.out"

################################################################################
# DO NOT MODIFY BELOW THIS LINE
################################################################################

# Export all variables
export NUM_GPUS MAX_GPU_WAIT JOB_START_DELAY JOB_CHECK_INTERVAL
export AMBERHOME PMEMD_CUDA BASE_DIR
export REST_WINDOW_TYPES DD_WINDOW_TYPES
export N_WINDOW_DT N_WINDOW_NTWPRT N_WINDOW_REMOVE_INFE BACKUP_MDIN_FILES
export LOG_DIR MAIN_LOG ERROR_LOG VERBOSE
export TRACKING_DIR JOB_QUEUE_FILE ACTIVE_JOBS_FILE COMPLETED_JOBS_FILE FAILED_JOBS_FILE
export SUCCESS_MARKER SUCCESS_CHECK_FILE USE_COLORS
export MAX_RETRIES CLEANUP_ON_COMPLETION
export MDIN_STAGES REQUIRED_FILES OUTPUT_FILES
