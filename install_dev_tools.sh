#!/usr/bin/env bash

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "Starting check and installation of tools..."

echo "Updating package lists..."
sudo apt update

if command_exists docker; then
    echo "Docker is already installed: $(docker --version)"
else
    echo "Installing Docker..."
    sudo apt install -y docker.io
    sudo systemctl enable --now docker
    echo "Docker installed successfully."
fi

if command_exists docker-compose || docker compose version >/dev/null 2>&1; then
    echo "Docker Compose is already installed."
else
    echo "Installing Docker Compose..."
    sudo apt install -y docker-compose
    echo "Docker Compose installed successfully."
fi

if command_exists python; then
    echo "Python is already installed: $(python --version)"
else
    echo "Installing Python..."
    sudo apt install -y python3 python3-pip python-is-python3
    echo "Python installed successfully."
fi

if ! command_exists pip; then
    echo "Installing pip..."
    sudo apt install -y python3-pip
fi

if python -c "import django" >/dev/null 2>&1; then
    echo "Django is already installed: $(python -m django --version)"
else
    echo "Installing Django via pip..."
    pip install django --break-system-packages
    echo "Django installed successfully."
fi

echo "All tools have been checked and are ready to use."

