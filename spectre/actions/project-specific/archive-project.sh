#!/bin/bash
# Archive management script for completed projects
# Usage: ./archive-project.sh <project_path> [year]

set -e

PROJECT_PATH="$1"
ARCHIVE_YEAR="${2:-$(date +%Y)}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$HOME/dev/archives/$ARCHIVE_YEAR}"
LOG_FILE="${LOG_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/spectre-suite/archive-projects.log}"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

if [ -z "$PROJECT_PATH" ]; then
    echo "Usage: $0 <project_path> [year]"
    echo "Example: $0 ~/dev/old-project 2025"
    exit 1
fi

if [ ! -d "$PROJECT_PATH" ]; then
    echo "Error: Directory $PROJECT_PATH does not exist"
    exit 1
fi

PROJECT_NAME=$(basename "$PROJECT_PATH")
ARCHIVE_PATH="$ARCHIVE_DIR/$PROJECT_NAME.tar.gz"

echo "=== Project Archive - $(date) ===" >> "$LOG_FILE"
echo "Archiving: $PROJECT_PATH" >> "$LOG_FILE"
echo "To: $ARCHIVE_PATH" >> "$LOG_FILE"

# Create archive directory if it doesn't exist
mkdir -p "$ARCHIVE_DIR"

# Check if archive already exists
if [ -f "$ARCHIVE_PATH" ]; then
    echo "Warning: Archive already exists at $ARCHIVE_PATH"
    read -p "Overwrite? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Archive cancelled"
        exit 0
    fi
    rm "$ARCHIVE_PATH"
fi

# Create the archive
echo "Creating archive..."
tar -czf "$ARCHIVE_PATH" -C "$(dirname "$PROJECT_PATH")" "$(basename "$PROJECT_PATH")"

ARCHIVE_SIZE=$(du -sh "$ARCHIVE_PATH" | cut -f1)
echo "Archive created: $ARCHIVE_PATH ($ARCHIVE_SIZE)" >> "$LOG_FILE"

# Ask if user wants to remove the original directory
read -p "Remove original directory $PROJECT_PATH? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing original directory..." >> "$LOG_FILE"
    rm -rf "$PROJECT_PATH"
    echo "Original directory removed" >> "$LOG_FILE"
fi

echo "Project archive completed at $(date)" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "Archive created successfully: $ARCHIVE_PATH ($ARCHIVE_SIZE)"
echo "Log saved to: $LOG_FILE"
