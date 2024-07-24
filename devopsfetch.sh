#!/bin/bash

# Activate the virtual environment
# source /usr/local/bin/devopsfetch/.venv/bin/activate
source ./.venv/bin/activate

# Run the Python script with sudo
sudo python3 ./main.py "$@"
