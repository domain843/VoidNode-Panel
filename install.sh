#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run this script with root privileges (sudo bash install.sh)"
  exit 1
fi

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="/opt/voidnode"

clear
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}     VOIDNODE PANEL INSTALLER MENU        ${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""
echo "  1. Run on Direct Port (IP:8989 - No Domain needed)"
echo "  2. Connect Custom Domain (Nginx + SSL)"
echo ""
read -p "Enter your choice [1 or 2]: " choice

echo "[ * ] Updating system packages..."
apt update && apt upgrade -y
apt install -y python3 python3-pip python3-venv git curl ufw

echo "[ * ] Cloning VoidNode repository..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi
git clone https://github.com/domain843/VoidNode-Panel.git "$INSTALL_DIR"

echo "[ * ] Setting up Python environment..."
cd "$INSTALL_DIR/backend" || exit 1
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "[ * ] Creating background system service..."
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

if [ "$choice" == "2" ]; then
    echo ""
    read -p "Enter your domain/subdomain (e.g., panel.yourdomain.com): " PANEL_DOMAIN
    read -p "Enter your email address for SSL: " ADMIN_EMAIL

    if [ -n "$PANEL_DOMAIN" ]; then
        apt install -y nginx certbot python3-certbot-nginx
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

        if [ -n "$ADMIN_EMAIL" ]; then
            certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect || true
        fi
        
        echo ""
        echo -e "${GREEN}[ OK ] Panel successfully configured with Domain!${NC}"
        echo -e "${GREEN}[ OK ] Access at: https://$PANEL_DOMAIN${NC}"
    fi
else
    SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    echo ""
    echo -e "${GREEN}[ OK ] VoidNode Successfully Installed!${NC}"
    echo -e "${GREEN}[ OK ] Access your panel directly on port: http://$SERVER_IP:8989${NC}"
fi
echo ""
