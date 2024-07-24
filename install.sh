#!/bin/bash

# Create and set permissions for the log file
sudo touch /var/log/devopsfetch.log
sudo chown root:root /var/log/devopsfetch.log

# Copy the script and make it executable
sudo cp devopsfetch.sh prettytable.sh /usr/local/bin/devopsfetch
sudo chmod +x /usr/local/bin/devopsfetch

# Create the wrapper script
cat << 'EOF' | sudo tee /usr/local/bin/devopsfetch-wrapper.sh > /dev/null
#!/bin/bash
/usr/local/bin/devopsfetch --time $(date +'%Y-%m-%d')
EOF

# Make the wrapper script executable
sudo chmod +x /usr/local/bin/devopsfetch-wrapper.sh

# Create a systemd service file
cat << 'EOF' | sudo tee /etc/systemd/system/devopsfetch.service > /dev/null
[Unit]
Description=DevOps Fetch Tool
After=network.target

[Service]
ExecStart=/usr/local/bin/devopsfetch-wrapper.sh
Restart=always
User=root
StandardOutput=journal
StandardError=inherit

[Install]
WantedBy=multi-user.target
EOF

# Create a logrotate configuration file
cat << 'EOF' | sudo tee /etc/logrotate.d/devopsfetch > /dev/null
/var/log/devopsfetch.log {
    size 10M
    rotate 5
    compress
    missingok
    notifempty
    create 0644 root root
    postrotate
        # Optionally, you can restart the service if needed
        # systemctl restart devopsfetch.service > /dev/null
    endscript
}
EOF

# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable and start the service
sudo systemctl enable devopsfetch.service
sudo systemctl start devopsfetch.service

echo "Installation and setup completed."
