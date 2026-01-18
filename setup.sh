#!/bin/bash

set -e  # Exit on any error

# Ensure sudo is available and cache credentials upfront
sudo -v
echo "Sudo cached. Script will proceed with elevated commands."

# --- Create Required Folders ---
echo "Creating required directories..."
mkdir -p $HOME/immich
mkdir -p $HOME/pictures
mkdir -p $HOME/download  # Samba share for downloads
mkdir -p $HOME/media     # Samba share for media files

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
   server smb encrypt = no
   smb encrypt = off

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
   guest ok = yes
   read only = no
   browseable = yes
   public = yes

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
cd $HOME/immich

echo "Downloading Immich docker-compose file..."
wget https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
echo "Downloading Immich environment file..."
wget https://github.com/immich-app/immich/releases/latest/download/example.env -O .env

# Security: Generate JWT Secret
JWT_SECRET=$(openssl rand -base64 32)
sed -i "s/jwt_secret_here/$JWT_SECRET/" .env

# Modify Docker-Compose to map your external folder
# We use 'sed' to add the volume mapping to the immich-server and immich-microservices sections
sed -i "/volumes:/a \      - $HOME/pictures:/external_photos" docker-compose.yml

# Start the containers
sudo docker compose up -d

# 4. Install and Configure Pi-hole
echo "Setting up Pi-hole..."
mkdir -p $HOME/pihole
cd $HOME/pihole

echo "Downloading Pi-hole docker-compose file..."
wget https://raw.githubusercontent.com/pi-hole/docker-pi-hole/master/docker-compose.yml.example -O docker-compose.yml

echo "Configuring Pi-hole..."
# Set a default admin password (user should change this)
sed -i 's/# WEBPASSWORD=/WEBPASSWORD=admin123/g' docker-compose.yml

# Start Pi-hole container
sudo docker compose up -d

echo "Pi-hole setup complete. Update the WEBPASSWORD in docker-compose.yml for security."

# 5. Final Configuration
echo ""
echo "======================================================="
echo "IMPORTANT: Log out and back in for Docker permissions"
echo "======================================================="
echo "The script has added your user to the Docker group."
echo "You must log out and back in for this to take effect."
read -p "Press Enter once you have logged out and back in: "

# 6. Finalize
sudo systemctl restart smbd

clear
echo "-------------------------------------------------------"
echo "NAS SETUP COMPLETE!"
echo "-------------------------------------------------------"
echo "USER ACTIONS REQUIRED:"
echo ""
echo "1. Setting Samba Password..."
sudo smbpasswd -a $USER

echo "ACCESS LINKS:"
echo "- Web Dashboard (VMs): https://$(hostname -I | awk '{print $1}'):9090"
echo "- Immich (Photos): http://$(hostname -I | awk '{print $1}'):2283"
echo "- Pi-hole (DNS): http://$(hostname -I | awk '{print $1}')/admin"
echo "- Samba (Mac/ChromeOS): smb://$(hostname -I | awk '{print $1}')/pictures"
echo "-------------------------------------------------------"
echo "To finish Immich Setup: Go to 'External Libraries' in the web UI"
echo "and add the path: /external_photos"