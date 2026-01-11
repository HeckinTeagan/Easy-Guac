#!/bin/sh
set -eu

# --- Configuration ---
BASE_DIR="/opt/stacks/guacamole"
SCRIPT_NAME=$0

# --- Functions ---

show_help() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -i, --install      Skip the welcome screen and install immediately."
    echo "  -p, --purge        Completely remove all Guacamole containers, volumes, and data."
    echo "  -h, --help         Show this help message."
}

purge_guacamole() {
    echo "!!! WARNING: THIS WILL DELETE ALL GUACAMOLE DATA, VOLUMES, AND CONFIGS !!!"
    printf "Are you sure you want to proceed? (y/N): "
    read -r CONFIRM
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        echo "Purging Guacamole environment..."
        if [ -d "$BASE_DIR" ]; then
            cd "$BASE_DIR"
            docker compose down -v --remove-orphans || true
            cd /
            rm -rf "$BASE_DIR"
            echo "Purge complete. System is clean."
        else
            echo "Nothing to purge. Directory $BASE_DIR does not exist."
        fi
        exit 0
    else
        echo "Purge cancelled."
        exit 1
    fi
}

# --- 1. Handle Flags (Purge/Help First) ---

case "${1:-}" in
    -p|--purge)
        purge_guacamole
        ;;
    -h|--help)
        show_help
        exit 0
        ;;
esac

# --- 2. Interactive Welcome (Installer Only) ---

INSTALL_NOW=false
for arg in "$@"; do
    if [ "$arg" = "-i" ] || [ "$arg" = "--install" ]; then
        INSTALL_NOW=true
    fi
done

if [ "$INSTALL_NOW" = false ]; then
    clear
    echo "===================================================="
    echo "                    EASY GUAC"
    echo "===================================================="
    echo "This script provides a streamlined deployment of"
    echo "Apache Guacamole using Docker Containers."
    echo ""
    echo "WHAT THIS SCRIPT WILL DO:"
    echo "  1. Install & Configure Docker dependencies"
    echo "  2. Setup Guacamole, Guacd, and Postgres"
    echo "  3. Generate secure database credentials"
    echo "  4. Launch the web interface on Port 8080"
    echo ""
    echo "AVAILABLE FLAGS:"
    echo "  -i, --install    Skip this screen"
    echo "  -p, --purge      Remove all data"
    echo "  -h, --help       Show help"
    echo "===================================================="
    echo ""
    printf "Ready to begin the setup? (y/N): "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Setup cancelled."
        exit 0
    fi
fi

# --- 3. Main Setup Logic ---

echo "--- Starting Easy Guac Setup ---"

# 1. Self-Healing Environment Check
echo "Step 1: Verifying dependencies..."

PKG_MANAGER=""
if command -v apk >/dev/null; then PKG_MANAGER="apk (Alpine)";
elif command -v apt-get >/dev/null; then PKG_MANAGER="apt (Debian/Ubuntu)";
elif command -v dnf >/dev/null; then PKG_MANAGER="dnf (Fedora/RHEL)";
elif command -v pacman >/dev/null; then PKG_MANAGER="pacman (Arch)";
fi

if [ -n "$PKG_MANAGER" ]; then
    echo "--- System Identity: Found $PKG_MANAGER ---"
else
    echo "--- System Identity: Unknown Package Manager ---"
fi

install_dependencies() {
    case "$PKG_MANAGER" in
        "apk (Alpine)")
            echo "Installing via apk..."
            apk add docker docker-cli-compose openssl curl || return 1
            ;;
        "apt (Debian/Ubuntu)")
            echo "Installing via apt..."
            apt-get update && apt-get install -y docker.io docker-compose-v2 openssl curl || return 1
            ;;
        "dnf (Fedora/RHEL)")
            echo "Installing via dnf..."
            # Core install
            dnf install -y docker openssl curl || return 1
            # Fallback logic for Compose
            if ! dnf install -y docker-compose-plugin; then
                echo "docker-compose-plugin not found, trying docker-compose..."
                dnf install -y docker-compose || return 1
            fi
            ;;
        "pacman (Arch)")
            echo "Installing via pacman..."
            pacman -Sy --noconfirm docker docker-compose openssl curl || return 1
            ;;
        *)
            echo "Error: Could not determine how to install dependencies."
            echo "Please install docker, docker-compose, openssl, and curl manually."
            exit 1
            ;;
    esac
}

if ! command -v docker > /dev/null || ! command -v curl > /dev/null; then
    install_dependencies || { echo "Installation failed."; exit 1; }
fi

if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running. Attempting to start..."
    if command -v systemctl >/dev/null; then
        systemctl start docker || { echo "Failed to start Docker via systemctl"; exit 1; }
        systemctl enable docker >/dev/null 2>&1
    elif command -v service >/dev/null; then
        service docker start || { echo "Failed to start Docker via service"; exit 1; }
        [ -f /etc/alpine-release ] && rc-update add docker boot >/dev/null 2>&1
    fi
    sleep 2
fi

# 2. Directory Preparation
echo "Step 2: Preparing directories at $BASE_DIR..."
mkdir -p "$BASE_DIR/init"

# 3. Secret Generation (.env)
if [ ! -f "$BASE_DIR/.env" ]; then
    echo "Step 3: Generating unique database secrets..."
    DB_PASS=$(openssl rand -base64 12)
    cat <<EOF > "$BASE_DIR/.env"
POSTGRES_PASSWORD=$DB_PASS
GUAC_DB_USER=guac_user
GUAC_DB_NAME=guacamole_db
EOF
fi

# 4. Database Schema Initialization
if [ ! -s "$BASE_DIR/init/initdb.sql" ]; then
    echo "Step 4: Initializing Postgres schema..."
    docker pull -q guacamole/guacamole:latest
    docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --postgresql > "$BASE_DIR/init/initdb.sql"
fi

# 5. Write Docker Compose File
echo "Step 5: Writing Docker Compose configuration..."
cat <<EOF > "$BASE_DIR/docker-compose.yml"
services:
  guacd:
    image: guacamole/guacd
    container_name: guacd
    restart: unless-stopped
  postgres:
    image: postgres:15-alpine
    container_name: guac_db
    restart: unless-stopped
    environment:
      POSTGRES_DB: guacamole_db
      POSTGRES_USER: guac_user
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    volumes:
      - ./init:/docker-entrypoint-initdb.d:ro
      - guac_db_data:/var/lib/postgresql/data
  guacamole:
    image: guacamole/guacamole
    container_name: guac_web
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      GUACD_HOSTNAME: guacd
      POSTGRESQL_HOSTNAME: postgres
      POSTGRESQL_DATABASE: guacamole_db
      POSTGRESQL_USERNAME: guac_user
      POSTGRESQL_PASSWORD: \${POSTGRES_PASSWORD}
    depends_on:
      - guacd
      - postgres
volumes:
  guac_db_data:
EOF

# 6. Deployment
echo "Step 6: Launching containers..."
cd "$BASE_DIR"
docker compose up -d

# 7. High-Precision Health Check
echo "Step 7: Monitoring Internal Startup..."
GREEN='\033[0;32m'
NC='\033[0m'

printf "Checking Java..." >&2
until docker exec guac_web pgrep -f catalina >/dev/null 2>&1; do
    printf "." >&2
    sleep 1
done
printf "${GREEN} [STARTED]${NC}\n"

printf "Connecting to Database..." >&2
until docker exec guac_web timeout 1 bash -c 'cat < /dev/null > /dev/tcp/postgres/5432' >/dev/null 2>&1; do
    printf "." >&2
    sleep 1
done
printf "${GREEN} [CONNECTED]${NC}\n"

printf "Initializing Tomcat..." >&2
until docker exec guac_web timeout 1 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/8080' >&2 2>/dev/null; do
    printf "." >&2
    sleep 1
done
printf "${GREEN} [READY]${NC}\n"

printf "Verifying Web Interface..." >&2
until curl --connect-timeout 1 --output /dev/null --silent --head --fail http://127.0.0.1:8080/guacamole/; do
    printf "." >&2
    sleep 1
done
printf "${GREEN} [ONLINE]${NC}\n"

# --- Final Call to Action ---
SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || hostname -i | awk '{print $1}')

echo ""
echo "===================================================="
echo -e "${GREEN}SUCCESS: Easy Guac is fully operational!${NC}"
echo "===================================================="
echo -e "Access via one of the following URLs:"
echo -e "  Local (NAT/SSH):   http://127.0.0.1:8080/guacamole/"
echo -e "  Network (Bridged): http://${SERVER_IP}:8080/guacamole/"
echo "----------------------------------------------------"
echo "Username: guacadmin"
echo "Password: guacadmin"
echo "===================================================="
echo -e "${GREEN}HELP:${NC} Links not working? See the 'Networking' section"
echo "in the README for NAT and Port Forwarding guidance."
echo "===================================================="

# --- Final Exit to prevent looping ---
exit 0