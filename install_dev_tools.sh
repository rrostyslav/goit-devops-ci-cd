#!/usr/bin/env bash
#
# install_dev_tools.sh
#
# Checks for and installs the development tools required for the course on
# Ubuntu: Docker Engine (docker-ce), the Docker Compose plugin, Python 3.9+
# and Django.
#
# Target OS: Ubuntu 22.04 / 24.04 (uses apt).

# Minimum Python version required by the course.
REQUIRED_PYTHON_MAJOR=3
REQUIRED_PYTHON_MINOR=9

# Interpreter used for the pip / Django steps. May be switched to a specific
# version (e.g. python3.9) if the default python3 is too old.
PYTHON_BIN="python3"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --------------------------------------------------------------------------
# Docker helpers
# --------------------------------------------------------------------------

# Set up Docker's official apt repository (idempotent).
# Follows https://docs.docker.com/engine/install/ubuntu/
setup_docker_repo() {
    echo "Setting up Docker's official apt repository..."

    # Add Docker's official GPG key.
    sudo apt update
    sudo apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to apt sources (deb822 format).
    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update
}

echo "Starting check and installation of tools..."

echo "Updating package lists..."
sudo apt update

# --------------------------------------------------------------------------
# 1. Docker Engine (official docker-ce package)
# --------------------------------------------------------------------------
# We check specifically for the docker-ce package (not just the `docker`
# command), because the distro's unofficial docker.io package also provides a
# `docker` binary but is NOT what we want here.
if dpkg -s docker-ce >/dev/null 2>&1; then
    echo "Docker CE is already installed: $(docker --version)"
else
    echo "Installing Docker CE..."

    # Remove conflicting/unofficial packages first (per Docker docs).
    # $conflicting is intentionally left unquoted so it splits into arguments.
    conflicting=$(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null | cut -f1)
    if [ -n "$conflicting" ]; then
        echo "Removing conflicting packages: $conflicting"
        sudo apt remove -y $conflicting
    fi

    setup_docker_repo

    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker

    # Allow the current user to run docker without sudo (takes effect after
    # the next login). See Docker's Linux post-install steps.
    sudo usermod -aG docker "$(id -un)"

    echo "Docker CE installed successfully: $(docker --version)"
    echo "NOTE: log out and back in for the 'docker' group membership to take effect."
fi

# --------------------------------------------------------------------------
# 2. Docker Compose plugin (docker-compose-plugin -> 'docker compose')
# --------------------------------------------------------------------------
# The modern Compose is a Docker CLI plugin, invoked as `docker compose`.
if docker compose version >/dev/null 2>&1; then
    echo "Docker Compose plugin is already installed: $(docker compose version)"
else
    echo "Installing Docker Compose plugin..."
    # The plugin lives in Docker's repo; make sure it is configured.
    if [ ! -f /etc/apt/sources.list.d/docker.sources ]; then
        setup_docker_repo
    fi
    sudo apt install -y docker-compose-plugin
    echo "Docker Compose plugin installed successfully: $(docker compose version)"
fi

# --------------------------------------------------------------------------
# 3. Python 3.9+
# --------------------------------------------------------------------------
# Returns 0 if the given interpreter ($1) is >= the required version.
python_meets_min() {
    "$1" - <<PYEOF >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= ($REQUIRED_PYTHON_MAJOR, $REQUIRED_PYTHON_MINOR) else 1)
PYEOF
}

if command_exists python3; then
    echo "Python 3 is already installed: $(python3 --version)"
else
    echo "Installing Python 3..."
    sudo apt install -y python3 python3-pip python-is-python3
    echo "Python 3 installed successfully."
fi

# Verify the installed version actually satisfies the >= 3.9 requirement.
echo "Verifying Python version is >= ${REQUIRED_PYTHON_MAJOR}.${REQUIRED_PYTHON_MINOR}..."
if python_meets_min "$PYTHON_BIN"; then
    echo "OK: $("$PYTHON_BIN" --version) satisfies the >= ${REQUIRED_PYTHON_MAJOR}.${REQUIRED_PYTHON_MINOR} requirement."
else
    current_version=$("$PYTHON_BIN" --version 2>&1)
    echo "The default Python ($current_version) is older than ${REQUIRED_PYTHON_MAJOR}.${REQUIRED_PYTHON_MINOR}."
    echo "Installing Python 3.9 explicitly from the deadsnakes PPA..."
    sudo apt install -y software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt update
    # python3.9-venv provides the ensurepip wheels used to bootstrap pip below.
    sudo apt install -y python3.9 python3.9-venv
    PYTHON_BIN="python3.9"

    if python_meets_min "$PYTHON_BIN"; then
        echo "OK: $("$PYTHON_BIN" --version) installed."
    else
        echo "ERROR: could not provide Python >= ${REQUIRED_PYTHON_MAJOR}.${REQUIRED_PYTHON_MINOR}. Aborting." >&2
        exit 1
    fi
fi

# --------------------------------------------------------------------------
# 4. pip (checked before it is used to install Django)
# --------------------------------------------------------------------------
# Returns 0 if $PYTHON_BIN's environment is PEP 668 "externally managed"
# (recent Ubuntu), in which case pip needs --break-system-packages.
python_externally_managed() {
    "$PYTHON_BIN" - <<'PYEOF' >/dev/null 2>&1
import os, sys, sysconfig
marker = os.path.join(sysconfig.get_path("stdlib"), "EXTERNALLY-MANAGED")
raise SystemExit(0 if os.path.exists(marker) else 1)
PYEOF
}

# Make sure pip is correctly installed for $PYTHON_BIN before we rely on it.
ensure_pip() {
    if "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
        echo "pip is already correctly installed: $("$PYTHON_BIN" -m pip --version)"
        return 0
    fi

    echo "pip is not available for $PYTHON_BIN. Installing pip..."
    if [ "$PYTHON_BIN" = "python3" ]; then
        sudo apt install -y python3-pip
    else
        # For the deadsnakes interpreter, bootstrap pip with ensurepip.
        "$PYTHON_BIN" -m ensurepip --upgrade
    fi

    if "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
        echo "pip installed successfully: $("$PYTHON_BIN" -m pip --version)"
    else
        echo "ERROR: failed to install pip for $PYTHON_BIN. Aborting." >&2
        exit 1
    fi
}

# --------------------------------------------------------------------------
# 5. Django
# --------------------------------------------------------------------------
if "$PYTHON_BIN" -c "import django" >/dev/null 2>&1; then
    echo "Django is already installed: $("$PYTHON_BIN" -m django --version)"
else
    # Requirement: verify pip is correctly installed before using it.
    ensure_pip

    # Only pass --break-system-packages where it is actually needed (and
    # supported); older pip on e.g. Ubuntu 22.04 does not know the flag.
    pip_flags=()
    if python_externally_managed; then
        pip_flags+=(--break-system-packages)
    fi

    echo "Installing Django via pip..."
    "$PYTHON_BIN" -m pip install "${pip_flags[@]}" django
    echo "Django installed successfully: $("$PYTHON_BIN" -m django --version)"
fi

echo "All tools have been checked and are ready to use."
