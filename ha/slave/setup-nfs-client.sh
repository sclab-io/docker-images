#!/bin/bash

NFS_SERVER="ip1"          # Replace with the actual NFS server IP address
NFS_REMOTE_DIR="/mnt/nfs_share"     # Remote directory shared by the NFS server
LOCAL_MOUNT_DIR="/mnt/nfs_share"   # Local mount point on the client

echo "Installing NFS client package..."
sudo apt update
sudo apt install -y nfs-common

echo "Creating local mount directory: $LOCAL_MOUNT_DIR"
sudo mkdir -p $LOCAL_MOUNT_DIR

echo "Mounting NFS share: $NFS_SERVER:$NFS_REMOTE_DIR -> $LOCAL_MOUNT_DIR"
sudo mount -t nfs $NFS_SERVER:$NFS_REMOTE_DIR $LOCAL_MOUNT_DIR

# Add the NFS mount to /etc/fstab for automatic mounting on boot
echo "Updating /etc/fstab for automatic mounting on boot..."
echo "$NFS_SERVER:$NFS_REMOTE_DIR $LOCAL_MOUNT_DIR nfs defaults 0 0" | sudo tee -a /etc/fstab

echo "NFS client setup complete!"
echo "Mounted $NFS_SERVER:$NFS_REMOTE_DIR at $LOCAL_MOUNT_DIR"