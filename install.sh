#!/bin/bash
################################################################################
# BAT Automation Package - Installation Script
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR=""

show_help() {
    cat << EOF
BAT Automation Package - Installation

Usage: $0 [TARGET_DIR]

Arguments:
  TARGET_DIR    Directory containing fe/ folder (default: current directory)

Examples:
  # Install in current directory
  $0

  # Install in specific directory
  $0 /path/to/BAT/

  # Install in parent of fe/ directory
  $0 /path/to/BAT/fe/..

Description:
  Installs the automation package to TARGET_DIR.
  Creates necessary directories and makes scripts executable.

EOF
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo "=================================="
echo "BAT Automation Package Installer"
echo "=================================="
echo ""
echo "Target directory: $TARGET_DIR"
echo ""

# Check if fe/ directory exists
if [ ! -d "$TARGET_DIR/fe" ]; then
    echo "Error: fe/ directory not found in $TARGET_DIR"
    echo "Please run from BAT root directory or specify correct path"
    exit 1
fi

echo "✓ Found fe/ directory"

# Create lib directory if installing
if [ "$SCRIPT_DIR" != "$TARGET_DIR" ]; then
    echo "Copying package files..."
    cp -r "$SCRIPT_DIR"/* "$TARGET_DIR/"
    echo "✓ Files copied"
fi

# Make scripts executable
echo "Setting permissions..."
chmod +x "$TARGET_DIR"/*.sh
chmod +x "$TARGET_DIR"/lib/*.sh 2>/dev/null || true
echo "✓ Permissions set"

# Create logs directory
mkdir -p "$TARGET_DIR/logs"
echo "✓ Created logs directory"

echo ""
echo "=================================="
echo "Installation Complete!"
echo "=================================="
echo ""
echo "Quick Start:"
echo "  cd $TARGET_DIR"
echo "  ./run_automation.sh"
echo ""
echo "For help:"
echo "  ./run_automation.sh --help"
echo ""
echo "Documentation:"
echo "  README.md"
echo ""
