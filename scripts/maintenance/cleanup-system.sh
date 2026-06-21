#!/bin/bash
# System Cleanup Script
# Performs regular system maintenance tasks

echo "Starting system maintenance cleanup..."

# Clean package cache
echo "Cleaning DNF package cache..."
sudo dnf clean all

# Clean old journal logs (keep last 7 days)
echo "Cleaning old journal logs..."
sudo journalctl --vacuum-time=7d

# Clean temporary files
echo "Cleaning temporary files..."
sudo rm -rf /tmp/* /var/tmp/*

# Clean user cache
echo "Cleaning user cache..."
rm -rf ~/.cache/evolution/*
rm -rf ~/.cache/thumbnails/*
rm -rf ~/.cache/mozilla/firefox/*/cache2
rm -rf ~/.config/google-chrome/Default/Cache/*

# Clean old downloads (older than 30 days)
echo "Cleaning old downloads..."
find ~/Downloads -type f -mtime +30 -delete 2>/dev/null || true

# Clean trash
echo "Emptying trash..."
rm -rf ~/.local/share/Trash/*

# Docker system cleanup
echo "Cleaning Docker system..."
docker system prune -f --volumes

# Clean Docker build cache
echo "Cleaning Docker build cache..."
docker builder prune -f

echo "System cleanup completed!"
logger -p user.info "System maintenance cleanup completed"
