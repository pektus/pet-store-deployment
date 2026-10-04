#!/usr/bin/env bash
# ==============================================================================
# Pet Store Deployment Script for dev-server-vm (192.168.1.235)
# Usage:
#   ./deploy.sh --local
#   ./deploy.sh --gitea --version 1.0.1-RELEASE --token <GITEA_TOKEN> [--gitea-url http://192.168.1.233]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${APP_DIR}"

MODE="local"
VERSION=""
GITEA_URL="http://192.168.1.233"
GITEA_TOKEN=""
GITEA_OWNER="DevHome"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)
            MODE="local"
            shift
            ;;
        --gitea)
            MODE="gitea"
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --token)
            GITEA_TOKEN="$2"
            shift 2
            ;;
        --gitea-url)
            GITEA_URL="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--local | --gitea --version <VERSION> --token <TOKEN>]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

echo "=================================================================="
echo " Pet Store Application Deployment"
echo " Working Directory: ${APP_DIR}"
echo " Mode:              ${MODE}"
echo "=================================================================="

# Check Docker and Docker Compose
if ! command -v docker &>/dev/null; then
    echo "ERROR: 'docker' command not found. Please install Docker first."
    exit 1
fi

DOCKER_COMPOSE_CMD=""
if docker compose version &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "ERROR: Neither 'docker compose' nor 'docker-compose' found."
    exit 1
fi

# If mode is gitea, download artifacts from Gitea Package Registry
if [[ "${MODE}" == "gitea" ]]; then
    if [[ -z "${VERSION}" ]]; then
        echo "ERROR: --version is required for --gitea mode."
        exit 1
    fi
    if [[ -z "${GITEA_TOKEN}" ]]; then
        echo "ERROR: --token is required for --gitea mode."
        exit 1
    fi

    echo ">>> Downloading artifacts from Gitea Maven Package Registry for version ${VERSION}..."
    mkdir -p backend frontend

    # Clean version string (remove 'v' prefix if given)
    VERSION_CLEAN="${VERSION#v}"

    WAR_URL="${GITEA_URL}/api/packages/${GITEA_OWNER}/maven/com/petstore/pet-store-web/${VERSION_CLEAN}/pet-store-web-${VERSION_CLEAN}.war"
    ZIP_URL="${GITEA_URL}/api/packages/${GITEA_OWNER}/maven/com/petstore/pet-store-frontend/${VERSION_CLEAN}/pet-store-frontend-${VERSION_CLEAN}.zip"

    echo "Downloading WAR from: ${WAR_URL}"
    curl -f -s -L -H "Authorization: token ${GITEA_TOKEN}" -o backend/petstore.war "${WAR_URL}"

    echo "Downloading Frontend ZIP from: ${ZIP_URL}"
    curl -f -s -L -H "Authorization: token ${GITEA_TOKEN}" -o frontend/pet-store-frontend.zip "${ZIP_URL}"
fi

# Verify artifacts exist
if [[ ! -f "backend/petstore.war" ]]; then
    echo "ERROR: Missing 'backend/petstore.war'. Ensure the WAR artifact is staged before running."
    exit 1
fi

if [[ ! -f "frontend/pet-store-frontend.zip" ]]; then
    echo "ERROR: Missing 'frontend/pet-store-frontend.zip'. Ensure the frontend zip artifact is staged before running."
    exit 1
fi

if [[ ! -f "backend/conf/application.properties" ]]; then
    echo "ERROR: Missing 'backend/conf/application.properties'. Ensure the external configuration file is staged before running."
    exit 1
fi

# Ensure .env exists
if [[ ! -f ".env" ]]; then
    if [[ -f ".env.example" ]]; then
        echo ">>> Creating .env from .env.example..."
        cp .env.example .env
    fi
fi

# Build and start containers
echo ">>> Building and deploying Docker containers..."
${DOCKER_COMPOSE_CMD} up -d --build --remove-orphans

echo ">>> Waiting for services to become healthy..."
MAX_WAIT=120
WAITED=0
HEALTHY=false

while [[ ${WAITED} -lt ${MAX_WAIT} ]]; do
    if curl -f -s -m 2 http://localhost/ > /dev/null 2>&1 && curl -f -s -m 2 http://localhost/api/pets > /dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    echo "Waiting for frontend (http://localhost/) and backend (http://localhost/api/pets)... (${WAITED}s / ${MAX_WAIT}s)"
    sleep 5
    WAITED=$((WAITED + 5))
done

if [[ "${HEALTHY}" == "true" ]]; then
    echo "=================================================================="
    echo " SUCCESS: Pet Store is up and running!"
    echo " Frontend SPA URL: http://192.168.1.235"
    echo " Backend API URL:  http://192.168.1.235/api/pets"
    echo "=================================================================="
    exit 0
else
    echo "WARNING: Application health check timed out after ${MAX_WAIT}s."
    echo "Checking docker container statuses:"
    ${DOCKER_COMPOSE_CMD} ps
    echo "Recent backend logs:"
    ${DOCKER_COMPOSE_CMD} logs --tail=50 backend
    exit 1
fi
