#!/bin/bash

# Install dependencies
apt-get update
apt-get install -y python3 python3-pip docker.io nginx
pip3 install --upgrade pip

sudo touch /var/log/devopsfetch.log
cp main.py /usr/local/bin/devopsfetch
chmod +x /usr/local/bin/devopsfetch

# Create a systemd service file
cat << 'EOF' > /etc/systemd/system/devopsfetch.service
[Unit]
Description=DevOps Fetch Tool
After=network.target

[Service]
ExecStart=/usr/local/bin/devopsfetch --time $(date +'%Y-%m-%d')
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd to recognize the new service
systemctl daemon-reload

# Enable and start the service
systemctl enable devopsfetch.service
systemctl start devopsfetch.service

echo "Installation and setup completed."
