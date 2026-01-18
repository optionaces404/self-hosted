#!/bin/bash

# --- Configuration Section ---

# --- Create Required Folders ---
echo "Creating required directories..."
mkdir -p ~/immich
mkdir -p ~/pictures
mkdir -p ~/download  # Samba share for downloads
mkdir -p ~/media     # Samba share for media files

# 1. Install Required Tools and Services
echo "Installing required tools and services..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git vim build-essential openssh-server

echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo apt install -y docker-compose-plugin

echo "Installing KVM and Cockpit Web Dashboard..."
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst cockpit cockpit-machines
sudo systemctl enable --now libvirtd
sudo systemctl enable --now cockpit.socket

# 2. Configure Samba with Apple-Optimized Settings
echo "Configuring Samba..."
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
cat <<EOF | sudo tee -a /etc/samba/smb.conf

[global]
   vfs objects = fruit streams_xattr
   fruit:metadata = netatalk
   fruit:model = MacMini
   fruit:posix_rename = yes
   fruit:veto_appledouble = no
   fruit:nfs_aces = no

[pictures]
   path = $HOME/pictures
   writable = yes
   guest ok = no
   read only = no
   browseable = yes
   force user = $USER

[download]
   path = $HOME/download
   writable = yes
   guest ok = no
   read only = no
   browseable = yes
   force user = $USER

[media]
   path = $HOME/media
   writable = yes
   guest ok = no
   read only = no
   browseable = yes
   force user = $USER
EOF

# 3. Configure Immich with External Library Support
echo "Setting up Immich..."
cd ~/immich

wget -q https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
wget -q https://github.com/immich-app/immich/releases/latest/download/example.env -O .env

# Security: Generate JWT Secret
JWT_SECRET=$(openssl rand -base64 32)
sed -i "s/jwt_secret_here/$JWT_SECRET/" .env

# Modify Docker-Compose to map your external folder
# We use 'sed' to add the volume mapping to the immich-server and immich-microservices sections
sed -i "/volumes:/a \      - $HOME/pictures:/external_photos" docker-compose.yml

# Start the containers
sudo docker compose up -d

# 4. Finalize
sudo systemctl restart smbd

clear
echo "-------------------------------------------------------"
echo "NAS SETUP COMPLETE!"
echo "-------------------------------------------------------"
echo "USER ACTIONS REQUIRED:"
echo "1. Set Samba Password: sudo smbpasswd -a $USER"
echo "2. Log out and back in to enable Docker permissions."
echo ""
echo "ACCESS LINKS:"
echo "- Web Dashboard (VMs): https://$(hostname -I | awk '{print $1}'):9090"
echo "- Immich (Photos): http://$(hostname -I | awk '{print $1}'):2283"
echo "- Samba (Mac/ChromeOS): smb://$(hostname -I | awk '{print $1}')/pictures"
echo "-------------------------------------------------------"
echo "To finish Immich Setup: Go to 'External Libraries' in the web UI"
echo "and add the path: /external_photos"