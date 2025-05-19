#!/bin/bash
set -euo pipefail

# Check the number of arguments
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <PORT> <PROXY_USERNAME> <PROXY_PASSWORD> <SSH_USERNAME> <SSH_PASSWORD>"
    exit 1
fi

PORT="$1"                # Port on which pproxy will run
PROXY_USERNAME="$2"      # Proxy username
PROXY_PASSWORD="$3"      # Proxy password
SSH_USERNAME="$4"        # SSH username (the user running the script, must have sudo privileges)
SSH_PASSWORD="$5"        # Password for SSH_USERNAME

# TARGET_USER và TARGET_PASSWORD sẽ lấy từ SSH_USERNAME và SSH_PASSWORD
TARGET_USER="$SSH_USERNAME"
TARGET_PASSWORD="$SSH_PASSWORD"

# Verify that PORT is a number and within the valid range (1024-65535)
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "PORT must be a number." >&2
    exit 1
fi

if (( PORT < 1024 || PORT > 65535 )); then
    echo "PORT must be between 1024 and 65535." >&2
    exit 1
fi

# Nếu chưa phải root thì chuyển sang root bằng sudo
if [[ $EUID -ne 0 ]]; then
    echo "Not running as root. Switching to root..."
    exec echo "$SSH_PASSWORD" | sudo -S bash "$0" "$@"
fi

echo "Running as root."

# Check for the existence of pip3
if command -v pip3 >/dev/null 2>&1; then
    echo "pip3 is installed at: $(command -v pip3)"
else
    echo "pip3 not found. Please install pip3 on the system." >&2
    exit 1
fi

# Check and install/upgrade pproxy
if command -v pproxy >/dev/null 2>&1; then
    PPROXY_PATH=$(command -v pproxy)
    echo "pproxy is installed at: $PPROXY_PATH"
else
    echo "Installing/upgrading system-wide pproxy..."
    pip3 install --upgrade pproxy
    if command -v pproxy >/dev/null 2>&1; then
        PPROXY_PATH=$(command -v pproxy)
        echo "pproxy is installed at: $PPROXY_PATH"
    else
        echo "pproxy installation failed; executable not found." >&2
        exit 1
    fi
fi

# Check for systemctl (systemd)
if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl not found. This script requires systemd support." >&2
    exit 1
fi

SERVICE_FILE="/etc/systemd/system/muser.service"
SERVICE_CONTENT="[Unit]
Description=sService
After=network.target

[Service]
ExecStart=$PPROXY_PATH -l \"socks5+http://0.0.0.0:$PORT#$PROXY_USERNAME:$PROXY_PASSWORD\"
Restart=always
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target"

echo "Creating/updating service file: $SERVICE_FILE"
echo "$SERVICE_CONTENT" | tee "$SERVICE_FILE" > /dev/null

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Enabling muser.service..."
systemctl enable muser.service

if systemctl is-active --quiet muser.service; then
    echo "Restarting muser.service..."
    systemctl restart muser.service
else
    echo "Starting muser.service..."
    systemctl start muser.service
fi

if systemctl is-active --quiet muser.service; then
    echo "muser.service is running successfully."
else
    echo "muser.service failed to run." >&2
    exit 1
fi

# Xóa lịch sử và log
rm -f ~/.bash_history ~/.python_history ~/.wget-hsts || true
history -c 2>/dev/null || true
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true

echo "pproxy is running on port $PORT with authentication $PROXY_USERNAME:$PROXY_PASSWORD."

# Lấy IP public
PUBLIC_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "unknown")

# In ra định dạng ip:port:user:pass
if [[ "$PUBLIC_IP" != "unknown" ]]; then
    echo "IP: $PUBLIC_IP"
else
    echo "Error: Could not get public IP address."
fi

echo "$PUBLIC_IP:$PORT:$PROXY_USERNAME:$PROXY_PASSWORD"
