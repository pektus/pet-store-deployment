#!/usr/bin/env bash
# ==============================================================================
# Initialization Script for dev-server-vm (192.168.1.235)
# Run with: sudo bash init-dev-server.sh
# ==============================================================================

set -euo pipefail

DEPLOY_USER="jenkins"
DEPLOY_DIR="/opt/petstore"

echo "=================================================================="
echo " Initializing dev-server-vm (192.168.1.235) for Pet Store CI/CD"
echo "=================================================================="

# Check root / sudo
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root or with sudo."
   exit 1
fi

# Detect Package Manager
echo ">>> Detecting OS distribution..."
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    echo "ERROR: Unsupported package manager. Please install Docker manually."
    exit 1
fi

echo "Detected package manager: ${PKG_MGR}"

# Install base prerequisites
if [[ "${PKG_MGR}" == "apt" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release unzip tar ufw
elif [[ "${PKG_MGR}" == "dnf" || "${PKG_MGR}" == "yum" ]]; then
    ${PKG_MGR} install -y curl ca-certificates gnupg2 unzip tar firewalld
fi

# Install Docker Engine & Docker Compose plugin if not installed
if ! command -v docker &>/dev/null; then
    echo ">>> Installing Docker Engine via official Docker installation script..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm -f get-docker.sh
else
    echo ">>> Docker is already installed: $(docker --version)"
fi

# Ensure docker service is running and enabled on boot
systemctl enable --now docker

# Create deployment user if it doesn't exist
if ! id "${DEPLOY_USER}" &>/dev/null; then
    echo ">>> Creating deployment user '${DEPLOY_USER}'..."
    useradd -m -s /bin/bash "${DEPLOY_USER}"
    echo "User '${DEPLOY_USER}' created."
else
    echo ">>> User '${DEPLOY_USER}' already exists."
fi

# Add deployment user to docker group
echo ">>> Adding '${DEPLOY_USER}' to 'docker' group..."
usermod -aG docker "${DEPLOY_USER}"

# If an interactive sudo user is running the script, also add them to the docker group
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    echo ">>> Also adding SUDO_USER '${SUDO_USER}' to 'docker' group..."
    usermod -aG docker "${SUDO_USER}"
fi

# Configure SSH directory for the deploy user
USER_HOME=$(eval echo "~${DEPLOY_USER}")
SSH_DIR="${USER_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
touch "${AUTH_KEYS}"
chmod 600 "${AUTH_KEYS}"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${SSH_DIR}"

# Create application deployment directory
echo ">>> Setting up application directory at ${DEPLOY_DIR}..."
mkdir -p "${DEPLOY_DIR}/backend" "${DEPLOY_DIR}/frontend" "${DEPLOY_DIR}/scripts"
chown -R "${DEPLOY_USER}:docker" "${DEPLOY_DIR}"
chmod -R 775 "${DEPLOY_DIR}"

# Configure firewall rules (allow SSH 22 and HTTP 80)
echo ">>> Checking and configuring firewall..."
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    echo "Configuring UFW..."
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw reload
elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
    echo "Configuring firewalld..."
    firewall-cmd --permanent --add-port=22/tcp
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --reload
fi

echo "=================================================================="
echo " DEV-SERVER-VM SETUP COMPLETED SUCCESSFULLY!"
echo "=================================================================="
echo "Next step: Add your Jenkins agent's SSH public key into:"
echo "   ${AUTH_KEYS}"
echo ""
echo "Example command to add public key directly:"
echo "   echo '<PASTE_JENKINS_PUBLIC_KEY_HERE>' >> ${AUTH_KEYS}"
echo "   chown -R ${DEPLOY_USER}:${DEPLOY_USER} ${SSH_DIR}"
echo "=================================================================="
