#!/bin/bash

NFS_DIR="/mnt/nfs_share"

echo "install nfs server"
sudo apt update
sudo apt install -y nfs-kernel-server

echo "create nfs folder: $NFS_DIR"
sudo mkdir -p $NFS_DIR
sudo chown nobody:nogroup $NFS_DIR
sudo chmod 777 $NFS_DIR

echo "configure nfs server"
echo "$NFS_DIR *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
sudo exportfs -a
sudo systemctl restart nfs-kernel-server

echo "NFS server setup complete : $NFS_DIR"
