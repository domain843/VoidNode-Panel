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

INSTALL_DIR="/opt/voidnode"

show_menu() {
    clear
    echo -e "${CYAN}+------------------------------------------+${NC}"
    echo -e "${CYAN}|         VOIDNODE PANEL INSTALLER         |${NC}"
    echo -e "${CYAN}+------------------------------------------+${NC}"
    echo ""
    echo "  1. INSTALL PANEL"
    echo "  2. CANCEL"
    echo "  3. UNINSTALL PANEL"
    echo "  4. PANEL STATUS"
    echo ""
    echo -e "${CYAN}+------------------------------------------+${NC}"
    read -p "Enter your choice [1-4]: " choice

    case $choice in
        1) install_panel ;;
        2) echo "Cancelled."; exit 0 ;;
        3) uninstall_panel ;;
        4) status_panel ;;
        *) echo -e "${RED}Invalid choice!${NC}"; sleep 2; show_menu ;;
    esac
}

install_panel() {
    clear
    echo -e "${CYAN}=== INSTALLING VOIDNODE PANEL ===${NC}"
    echo ""
    read -p "Enter your panel domain/subdomain or IP: " PANEL_DOMAIN
    read -p "Enter your email address for SSL (optional): " ADMIN_EMAIL

    if [ -z "$PANEL_DOMAIN" ]; then
        echo -e "${RED}[ X ] Domain or IP cannot be empty! Exiting.${NC}"
        exit 1
    fi

    echo "[ * ] Updating system packages..."
    apt update && apt upgrade -y
    apt install -y python3 python3-pip python3-venv git curl nginx ufw

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

    echo "[ * ] Setting up web access..."
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
        apt install -y certbot python3-certbot-nginx
        certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect || true
    fi

    echo ""
    echo -e "${GREEN}[ OK ] VoidNode Successfully Installed!${NC}"
    echo -e "${GREEN}[ OK ] Access your panel at: http://$PANEL_DOMAIN${NC}"
    echo ""
    read -p "Press Enter to return to menu..." dummy
    show_menu
}

uninstall_panel() {
    clear
    echo -e "${RED}=== UNINSTALLING VOIDNODE PANEL ===${NC}"
    systemctl stop voidnode 2>/dev/null
    systemctl disable voidnode 2>/dev/null
    rm -f /etc/systemd/system/voidnode.service
    systemctl daemon-reload
    rm -f /etc/nginx/sites-available/voidnode /etc/nginx/sites-enabled/voidnode
    systemctl restart nginx 2>/dev/null
    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}[ OK ] VoidNode has been completely uninstalled.${NC}"
    echo ""
    read -p "Press Enter to return to menu..." dummy
    show_menu
}

status_panel() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}         VOIDNODE PANEL STATUS            ${NC}"
    echo -e "${CYAN}==========================================${NC}"

    if [ -d "$INSTALL_DIR" ]; then
        echo -e "[ ${GREEN}OK${NC} ] Installation : INSTALLED ($INSTALL_DIR)"
    else
        echo -e "[ ${RED}FAILED${NC} ] Installation : NOT INSTALLED"
    fi

    if systemctl is-active --quiet voidnode; then
        echo -e "[ ${GREEN}OK${NC} ] Service      : RUNNING (voidnode=active)"
    else
        echo -e "[ ${RED}FAILED${NC} ] Service      : INACTIVE / STOPPED"
    fi

    echo -e "[ ${GREEN}OK${NC} ] Port         : 8989 (listening)"
    echo -e "[ ${GREEN}OK${NC} ] Web Access   : AVAILABLE (http://127.0.0.1:8989)"
    
    if [ -d "$INSTALL_DIR/backend/.venv" ]; then
        PY_VER=$(/opt/voidnode/backend/.venv/bin/python --version 2>&1)
        echo -e "[ ${GREEN}OK${NC} ] Python venv  : $PY_VER ($INSTALL_DIR/backend/.venv)"
    fi

    echo ""
    echo "------------------------------------------"
    # Fetch system metrics
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
    RAM_PCT=$(free | awk '/Mem:/ {printf("%.1f"), $3/$2*100}')
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')

    echo "CPU Usage   : ${CPU_USAGE}%"
    echo "RAM Usage   : ${RAM_USED} MB / ${RAM_TOTAL} MB (${RAM_PCT}%)"
    echo "Disk Usage  : ${DISK_USAGE}"
    echo "=========================================="
    echo ""
    echo "1. BACK TO MENU"
    echo "2. EXIT"
    read -p "Choose [1-2]: " st_choice
    if [ "$st_choice" == "1" ]; then
        show_menu
    else
        exit 0
    fi
}

show_menu
