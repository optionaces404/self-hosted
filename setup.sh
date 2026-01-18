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

# 6. Install and Configure Portainer
echo "Setting up Portainer..."
mkdir -p $HOME/portainer

echo "Starting Portainer Docker container..."
sudo docker run -d \
  --name portainer \
  --restart=always \
  -p 8000:8000 \
  -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $HOME/portainer:/data \
  portainer/portainer-ce:latest

echo "Portainer setup complete."

# 6. Install and Configure Emby (Media Server)
echo "Setting up Emby..."
mkdir -p $HOME/emby

echo "Starting Emby Docker container..."
sudo docker run -d \
  --name emby \
  --restart=always \
  -p 8096:8096 \
  -p 8920:8920 \
  -v $HOME/emby:/config \
  -v $HOME/media:/media \
  -v $HOME/pictures:/pictures \
  emby/embyserver:latest

echo "Emby setup complete."

# 7. Install and Configure Duplicati (Backup)
echo "Setting up Duplicati..."
mkdir -p $HOME/duplicati

echo "Starting Duplicati Docker container..."
sudo docker run -d \
  --name duplicati \
  --restart=always \
  -p 8200:8200 \
  -v $HOME/duplicati:/data \
  -v $HOME:/source:ro \
  duplicati/duplicati:latest

echo "Duplicati setup complete."

# 8. Install and Configure Prometheus + Grafana (Monitoring)
echo "Setting up Prometheus..."
mkdir -p $HOME/prometheus
mkdir -p $HOME/grafana

# Create Prometheus config
cat > $HOME/prometheus/prometheus.yml <<'PROM'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
PROM

echo "Starting Prometheus Docker container..."
sudo docker run -d \
  --name prometheus \
  --restart=always \
  -p 9090:9090 \
  -v $HOME/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  -v $HOME/prometheus:/prometheus \
  prom/prometheus:latest

echo "Starting Node Exporter Docker container..."
sudo docker run -d \
  --name node-exporter \
  --restart=always \
  -p 9100:9100 \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -v /:/rootfs:ro \
  prom/node-exporter:latest

echo "Starting Grafana Docker container..."
sudo docker run -d \
  --name grafana \
  --restart=always \
  -p 3000:3000 \
  -v $HOME/grafana:/var/lib/grafana \
  grafana/grafana:latest

echo "Monitoring stack setup complete."

# 9. Configure Firewall (Last Step for Security)
echo ""
echo "Configuring firewall rules..."
sudo apt install -y ufw
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Open SSH for remote access
sudo ufw allow 22/tcp

# Open Samba (file sharing) - ports 137, 138, 139, 445
sudo ufw allow 137/udp
sudo ufw allow 138/udp
sudo ufw allow 139/tcp
sudo ufw allow 445/tcp

# Open Cockpit (VMs) - port 9090
sudo ufw allow 9090/tcp

# Open Immich (Photos) - port 2283
sudo ufw allow 2283/tcp

# Open Portainer (Docker) - port 9000
sudo ufw allow 9000/tcp

# Open Emby (Media Server) - port 8096
sudo ufw allow 8096/tcp

# Open Duplicati (Backup) - port 8200
sudo ufw allow 8200/tcp

# Open Prometheus (Monitoring) - port 9090
sudo ufw allow 9090/tcp

# Open Grafana (Dashboards) - port 3000
sudo ufw allow 3000/tcp

# Open Pi-hole DNS - ports 53 (TCP/UDP) and port 80 (web UI)
sudo ufw allow 53/tcp
sudo ufw allow 53/udp
sudo ufw allow 80/tcp

echo "Firewall configured successfully."

# 10. Final Configuration
echo ""
echo "======================================================="
echo "IMPORTANT: Log out and back in for Docker permissions"
echo "======================================================="
echo "The script has added your user to the Docker group."
echo "You must log out and back in for this to take effect."
read -p "Press Enter once you have logged out and back in: "

# 11. Finalize
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
echo "- Portainer (Docker): http://$(hostname -I | awk '{print $1}'):9000"
echo "- Emby (Media): http://$(hostname -I | awk '{print $1}'):8096"
echo "- Duplicati (Backup): http://$(hostname -I | awk '{print $1}'):8200"
echo "- Prometheus (Metrics): http://$(hostname -I | awk '{print $1}'):9090"
echo "- Grafana (Dashboards): http://$(hostname -I | awk '{print $1}'):3000"
echo "- Immich (Photos): http://$(hostname -I | awk '{print $1}'):2283"
echo "- Pi-hole (DNS): http://$(hostname -I | awk '{print $1}')/admin"
echo "- Samba (Mac/ChromeOS): smb://$(hostname -I | awk '{print $1}')/pictures"
echo "-------------------------------------------------------"
echo "To finish Immich Setup: Go to 'External Libraries' in the web UI"
echo "and add the path: /external_photos"