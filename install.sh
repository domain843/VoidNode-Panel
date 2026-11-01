#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run this script with root privileges (sudo bash install.sh)"
  exit 1
fi

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}        VOIDNODE PANEL INSTALLER          ${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

# Interactive prompts
read -p "Enter your panel domain or subdomain (e.g., panel.yourdomain.com): " PANEL_DOMAIN
read -p "Enter your email address for SSL certificate: " ADMIN_EMAIL

if [ -z "$PANEL_DOMAIN" ]; then
    echo -e "${RED}[ X ] Domain cannot be empty! Exiting.${NC}"
    exit 1
fi

INSTALL_DIR="/opt/voidnode"

echo "[ * ] Updating system packages and installing dependencies..."
apt update && apt upgrade -y
apt install -y python3 python3-pip python3-venv git curl nginx certbot python3-certbot-nginx ufw

echo "[ * ] Cloning VoidNode repository..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi
# REPLACE 'YOUR_GITHUB_USERNAME' WITH YOUR ACTUAL GITHUB USERNAME
git clone https://github.com/domain843/VoidNode-Panel.git "$INSTALL_DIR"

echo "[ * ] Setting up Python virtual environment..."
cd "$INSTALL_DIR/backend"
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "[ * ] Configuring systemd background daemon..."
cat > /etc/systemd/system/voidnode.service <<EOF
[Unit]
Description=VoidNode Control Daemon
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR/backend
ExecStart=$INSTALL_DIR/backend/.venv/bin/python app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable voidnode
systemctl start voidnode

echo "[ * ] Configuring Nginx reverse proxy..."
cat > /etc/nginx/sites-available/voidnode <<EOF
server {
    listen 80;
    server_name $PANEL_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8989;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/voidnode /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

echo "[ * ] Obtaining SSL Certificate via Let's Encrypt..."
certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect || echo -e "${RED}[ ! ] SSL setup skipped. Ensure your domain DNS points to this VPS IP, then run: sudo certbot --nginx${NC}"

echo ""
echo -e "${GREEN}[ OK ] VoidNode Installation Complete!${NC}"
echo -e "${GREEN}[ OK ] Access your panel securely at: https://$PANEL_DOMAIN${NC}"
