#!/bin/bash
# Setup UFW firewall rules for LocalSend
# LocalSend uses port 53317 for both TCP and UDP

set -e

echo "Setting up UFW firewall rules for LocalSend..."

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    echo "Warning: UFW is not installed. Skipping firewall configuration."
    exit 0
fi

# Allow LocalSend port for TCP (file transfers)
echo "Adding UFW rule for LocalSend TCP (port 53317)..."
sudo ufw allow 53317/tcp comment 'LocalSend'

# Allow LocalSend port for UDP (device discovery)
echo "Adding UFW rule for LocalSend UDP (port 53317)..."
sudo ufw allow 53317/udp comment 'LocalSend'

echo "LocalSend firewall rules added successfully!"
echo ""
echo "UFW Status:"
sudo ufw status verbose | grep -E "(53317|Status:)"
