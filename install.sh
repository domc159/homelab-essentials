#!/usr/bin/env bash
# =============================================================================
#  HomeServer Install Script
#  Installs: Seafile · BentoPDF · IT-Tools · FreshRSS · Immich · Joplin
#            Paperless-ngx · n8n · OnlyOffice · Webmin
#  Requirements: Ubuntu Server, root or sudo
# =============================================================================
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }
step() { echo -e "\n${BOLD}${BLUE}== $* ==${NC}"; }

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Run as root: sudo bash install.sh"

# ── Paths ─────────────────────────────────────────────────────────────────────
HOMELAB=/home/homelab
DATA=/home/homelab_data
SHARED=/home/data

# ── Detect server IP ──────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
info "Detected server IP: ${SERVER_IP}"

# =============================================================================
#  1. DOCKER
# =============================================================================
step "1. Installing Docker"
if ! command -v docker &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    log "Docker installed"
else
    log "Docker already present: $(docker --version)"
fi

if ! docker compose version &>/dev/null; then
    apt-get install -y -qq docker-compose-plugin
    log "docker-compose-plugin installed"
else
    log "Docker Compose already present"
fi

# =============================================================================
#  2. WEBMIN  (port 10000, https)
# =============================================================================
#  2. WEBMIN  (port 10000, https)
# =============================================================================
step "2. Installing Webmin"

# ── Helper: nuke every trace of previous (partial) Webmin repo setup ──────────
webmin_purge_repo_state() {
    info "Webmin: purging any previous repo state..."

    # Keys -- all known filenames left by setup-repo.sh or our own scripts
    rm -f /usr/share/keyrings/ubuntu-webmin-developers.gpg \
          /usr/share/keyrings/webmin.gpg \
          /usr/share/keyrings/webmin-*.gpg

    # List files -- classic .list format
    rm -f /etc/apt/sources.list.d/webmin.list \
          /etc/apt/sources.list.d/webmin-*.list

    # deb822 .sources format (newer Ubuntu)
    rm -f /etc/apt/sources.list.d/webmin.sources \
          /etc/apt/sources.list.d/webmin-*.sources

    # Stray entries inside /etc/apt/sources.list itself
    if [[ -f /etc/apt/sources.list ]]; then
        sed -i '/download\.webmin\.com/d' /etc/apt/sources.list
    fi

    # Refresh apt state so it no longer errors on the removed repos
    apt-get update -qq 2>/dev/null || true
}

# ── Install via direct .deb (most robust -- zero repo involvement) ─────────────
webmin_install_deb() {
    info "Webmin: downloading current .deb directly from webmin.com..."
    local DEB=/tmp/webmin-current.deb
    curl -fsSL https://www.webmin.com/download/deb/webmin-current.deb -o "$DEB"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --install-recommends "$DEB"
    rm -f "$DEB"
}

# ── Install via apt repo (stable only) ────────────────────────────────────────
webmin_install_repo() {
    info "Webmin: setting up stable apt repo..."
    local KEY=/usr/share/keyrings/webmin.gpg
    local LIST=/etc/apt/sources.list.d/webmin.list
    curl -fsSL https://www.webmin.com/jcameron-key.asc \
        | gpg --dearmor --yes -o "$KEY"
    printf 'deb [signed-by=%s] https://download.webmin.com/download/newkey/repository stable contrib\n' \
        "$KEY" > "$LIST"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq webmin --install-recommends
}

if [[ -f /etc/webmin/config ]]; then
    log "Webmin already installed"
else
    # Detect OS family BEFORE any apt call
    OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' | tr '[:upper:]' '[:lower:]')
    OS_LIKE=$(grep -oP '(?<=^ID_LIKE=).+' /etc/os-release 2>/dev/null | tr -d '"' | tr '[:upper:]' '[:lower:]' || true)

    if echo "${OS_ID} ${OS_LIKE}" | grep -qE 'rhel|fedora|centos|alma|rocky|oracle'; then
        # ── RHEL family ──────────────────────────────────────────────────────
        info "Webmin: RHEL-family detected, using dnf..."
        curl -fsSL https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh \
            -o /tmp/webmin-setup-repo.sh
        sh /tmp/webmin-setup-repo.sh --force
        rm -f /tmp/webmin-setup-repo.sh
        dnf install -y webmin

    else
        # ── Debian/Ubuntu family ─────────────────────────────────────────────
        info "Webmin: Debian-family detected (${OS_ID})..."

        # STEP 1: clean all previous state BEFORE any apt call
        webmin_purge_repo_state

        # STEP 2: install dependencies (apt is clean now)
        apt-get install -y -qq perl gnupg2 curl apt-transport-https

        # STEP 3: try repo method; on any failure fall back to direct .deb
        if webmin_install_repo 2>/tmp/webmin_err; then
            info "Webmin: repo install succeeded"
        else
            warn "Webmin: repo install failed -- $(tail -1 /tmp/webmin_err)"
            warn "Webmin: falling back to direct .deb download..."
            # Re-purge so apt is not broken before the fallback
            webmin_purge_repo_state
            webmin_install_deb
        fi
        rm -f /tmp/webmin_err
    fi

    # Verify
    if [[ -f /etc/webmin/config ]]; then
        log "Webmin installed -- accessible at https://${SERVER_IP}:10000"
    else
        err "Webmin installation failed -- review the output above"
    fi
fi

# =============================================================================
#  3. DIRECTORIES
# =============================================================================
step "3. Creating directory structure"
mkdir -p "$HOMELAB"
mkdir -p "$DATA"/{seafile,immich,joplin,paperless,freshrss,n8n,onlyoffice}
mkdir -p "$DATA"/seafile/{data,mysql}
mkdir -p "$DATA"/immich/{upload,postgres}
mkdir -p "$DATA"/joplin/postgres
mkdir -p "$DATA"/paperless/{data,media,export,consume,postgres}
mkdir -p "$DATA"/freshrss/{data,extensions}
mkdir -p "$DATA"/n8n/data
chown 1000:1000 "$DATA"/n8n/data
mkdir -p "$DATA"/onlyoffice/{data,logs,fonts}
mkdir -p "$SHARED"
chmod -R 755 "$DATA" "$SHARED"
log "Directories created"

# =============================================================================
#  4. GENERATE .env
# =============================================================================
step "4. Generating .env"

if [[ -f "$HOMELAB/.env" ]]; then
    warn ".env already exists -- skipping password generation to avoid overwrite"
else

rand() { openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c"$1"; }

SEAFILE_DB_ROOT=$(rand 28)
SEAFILE_DB_PASS=$(rand 28)
IMMICH_DB_PASS=$(rand 28)
JOPLIN_DB_PASS=$(rand 28)
PAPERLESS_DB_PASS=$(rand 28)
PAPERLESS_SECRET=$(rand 48)
N8N_KEY=$(rand 32)
OO_JWT=$(rand 32)

cat > "$HOMELAB/.env" <<EOF
# =============================================================
#  HomeServer .env  --  DO NOT COMMIT TO GIT
#  Generated: $(date)
# =============================================================

# -- Server --------------------------------------------------
SERVER_IP=${SERVER_IP}
TZ=Europe/Ljubljana

# -- Seafile -------------------------------------------------
SEAFILE_ADMIN_EMAIL=me@mail.com
SEAFILE_ADMIN_PASSWORD=admin
SEAFILE_SERVER_HOSTNAME=${SERVER_IP}
SEAFILE_DB_ROOT_PASS=${SEAFILE_DB_ROOT}
SEAFILE_DB_PASS=${SEAFILE_DB_PASS}

# -- Immich --------------------------------------------------
IMMICH_DB_PASS=${IMMICH_DB_PASS}
IMMICH_DB_NAME=immich
IMMICH_DB_USER=immich

# -- Joplin --------------------------------------------------
JOPLIN_DB_PASS=${JOPLIN_DB_PASS}
JOPLIN_DB_NAME=joplin
JOPLIN_DB_USER=joplin

# -- Paperless-ngx -------------------------------------------
PAPERLESS_DB_PASS=${PAPERLESS_DB_PASS}
PAPERLESS_SECRET_KEY=${PAPERLESS_SECRET}

# -- n8n -----------------------------------------------------
N8N_ENCRYPTION_KEY=${N8N_KEY}
N8N_PROTOCOL=http
N8N_SECURE_COOKIE=false

# -- OnlyOffice ----------------------------------------------
ONLYOFFICE_JWT_SECRET=${OO_JWT}
EOF

chmod 600 "$HOMELAB/.env"
log ".env created with random passwords"
fi

# =============================================================================
#  5. GENERATE docker-compose.yml
# =============================================================================
step "5. Generating docker-compose.yml"

# Load .env so path variables are available for volume mounts
source "$HOMELAB/.env"

cat > "$HOMELAB/docker-compose.yml" <<COMPOSE
# =============================================================
#  HomeServer -- docker-compose.yml
#  Generated by install.sh -- do not edit manually
# =============================================================

services:

# =============================================================
#  SEAFILE  --  port 8060
# =============================================================
  seafile-mysql:
    image: mariadb:10.11
    container_name: seafile-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: \${SEAFILE_DB_ROOT_PASS}
      MYSQL_LOG_CONSOLE: "true"
    volumes:
      - ${DATA}/seafile/mysql:/var/lib/mysql
    networks:
      - seafile-net

  seafile-memcached:
    image: memcached:1.6-alpine
    container_name: seafile-memcached
    restart: unless-stopped
    entrypoint: memcached -m 256
    networks:
      - seafile-net

  seafile:
    image: seafileltd/seafile-mc:latest
    container_name: seafile
    restart: unless-stopped
    ports:
      - "8060:80"
    volumes:
      - ${DATA}/seafile/data:/shared
    environment:
      DB_HOST: seafile-mysql
      DB_ROOT_PASSWD: \${SEAFILE_DB_ROOT_PASS}
      SEAFILE_ADMIN_EMAIL: \${SEAFILE_ADMIN_EMAIL}
      SEAFILE_ADMIN_PASSWORD: \${SEAFILE_ADMIN_PASSWORD}
      SEAFILE_SERVER_LETSENCRYPT: "false"
      SEAFILE_SERVER_HOSTNAME: \${SEAFILE_SERVER_HOSTNAME}
      TIME_ZONE: \${TZ}
    depends_on:
      - seafile-mysql
      - seafile-memcached
    networks:
      - seafile-net

# =============================================================
#  BENTOPDF  --  port 8061
# =============================================================
  bentopdf:
    image: ghcr.io/alam00000/bentopdf:latest
    container_name: bentopdf
    restart: unless-stopped
    ports:
      - "8061:8080"
    networks:
      - homelab-net

# =============================================================
#  IT-TOOLS  --  port 8062
# =============================================================
  it-tools:
    image: corentinth/it-tools:latest
    container_name: it-tools
    restart: unless-stopped
    ports:
      - "8062:80"
    networks:
      - homelab-net

# =============================================================
#  FRESHRSS  --  port 8063  (sync every 15 minutes)
# =============================================================
  freshrss:
    image: freshrss/freshrss:latest
    container_name: freshrss
    restart: unless-stopped
    ports:
      - "8063:80"
    volumes:
      - ${DATA}/freshrss/data:/var/www/FreshRSS/data
      - ${DATA}/freshrss/extensions:/var/www/FreshRSS/extensions
    environment:
      TZ: \${TZ}
      CRON_MIN: "*/15"
      FRESHRSS_ENV: production
    networks:
      - homelab-net

# =============================================================
#  IMMICH  --  port 8064
# =============================================================
  immich-postgres:
    image: ghcr.io/immich-app/postgres:14-vectorchord0.3.0-pgvectors0.3.0
    container_name: immich-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: \${IMMICH_DB_NAME}
      POSTGRES_USER: \${IMMICH_DB_USER}
      POSTGRES_PASSWORD: \${IMMICH_DB_PASS}
    volumes:
      - ${DATA}/immich/postgres:/var/lib/postgresql/data
    networks:
      - immich-net

  immich-redis:
    image: redis:7-alpine
    container_name: immich-redis
    restart: unless-stopped
    networks:
      - immich-net

  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    container_name: immich-server
    restart: unless-stopped
    ports:
      - "8064:2283"
    volumes:
      - ${DATA}/immich/upload:/usr/src/app/upload
      - ${SHARED}:/mnt/shared:ro
      - /etc/localtime:/etc/localtime:ro
    environment:
      DB_HOSTNAME: immich-postgres
      DB_DATABASE_NAME: \${IMMICH_DB_NAME}
      DB_USERNAME: \${IMMICH_DB_USER}
      DB_PASSWORD: \${IMMICH_DB_PASS}
      REDIS_HOSTNAME: immich-redis
      TZ: \${TZ}
    depends_on:
      - immich-postgres
      - immich-redis
    networks:
      - immich-net

  immich-machine-learning:
    image: ghcr.io/immich-app/immich-machine-learning:release
    container_name: immich-ml
    restart: unless-stopped
    volumes:
      - immich-ml-cache:/cache
    networks:
      - immich-net

# =============================================================
#  JOPLIN SERVER  --  port 8065
# =============================================================
  joplin-postgres:
    image: postgres:15-alpine
    container_name: joplin-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: \${JOPLIN_DB_NAME}
      POSTGRES_USER: \${JOPLIN_DB_USER}
      POSTGRES_PASSWORD: \${JOPLIN_DB_PASS}
    volumes:
      - ${DATA}/joplin/postgres:/var/lib/postgresql/data
    networks:
      - joplin-net

  joplin:
    image: joplin/server:latest
    container_name: joplin
    restart: unless-stopped
    ports:
      - "8065:22300"
    environment:
      APP_BASE_URL: http://\${SERVER_IP}:8065
      APP_PORT: 22300
      DB_CLIENT: pg
      POSTGRES_HOST: joplin-postgres
      POSTGRES_DATABASE: \${JOPLIN_DB_NAME}
      POSTGRES_USER: \${JOPLIN_DB_USER}
      POSTGRES_PASSWORD: \${JOPLIN_DB_PASS}
      POSTGRES_PORT: 5432
    depends_on:
      - joplin-postgres
    networks:
      - joplin-net

# =============================================================
#  PAPERLESS-NGX  --  port 8066
# =============================================================
  paperless-postgres:
    image: postgres:15-alpine
    container_name: paperless-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: paperless
      POSTGRES_USER: paperless
      POSTGRES_PASSWORD: \${PAPERLESS_DB_PASS}
    volumes:
      - ${DATA}/paperless/postgres:/var/lib/postgresql/data
    networks:
      - paperless-net

  paperless-redis:
    image: redis:7-alpine
    container_name: paperless-redis
    restart: unless-stopped
    networks:
      - paperless-net

  paperless:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    container_name: paperless
    restart: unless-stopped
    ports:
      - "8066:8000"
    volumes:
      - ${DATA}/paperless/data:/usr/src/paperless/data
      - ${DATA}/paperless/media:/usr/src/paperless/media
      - ${DATA}/paperless/export:/usr/src/paperless/export
      - ${DATA}/paperless/consume:/usr/src/paperless/consume
    environment:
      PAPERLESS_REDIS: redis://paperless-redis:6379
      PAPERLESS_DBHOST: paperless-postgres
      PAPERLESS_DBPASS: \${PAPERLESS_DB_PASS}
      PAPERLESS_SECRET_KEY: \${PAPERLESS_SECRET_KEY}
      PAPERLESS_TIME_ZONE: \${TZ}
      PAPERLESS_OCR_LANGUAGE: eng
      PAPERLESS_URL: http://\${SERVER_IP}:8066
    depends_on:
      - paperless-postgres
      - paperless-redis
    networks:
      - paperless-net

# =============================================================
#  N8N  --  port 8067
# =============================================================
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    user: "1000:1000"
    ports:
      - "8067:5678"
    volumes:
      - ${DATA}/n8n/data:/home/node/.n8n
      - ${SHARED}:/mnt/shared
    environment:
      N8N_ENCRYPTION_KEY: \${N8N_ENCRYPTION_KEY}
      N8N_HOST: \${SERVER_IP}
      N8N_PORT: 5678
      N8N_PROTOCOL: \${N8N_PROTOCOL}
      WEBHOOK_URL: http://\${SERVER_IP}:8067
      N8N_SECURE_COOKIE: false
      GENERIC_TIMEZONE: \${TZ}
    networks:
      - homelab-net

# =============================================================
#  ONLYOFFICE  --  port 8068
# =============================================================
  onlyoffice:
    image: onlyoffice/documentserver:latest
    container_name: onlyoffice
    restart: unless-stopped
    ports:
      - "8068:80"
    volumes:
      - ${DATA}/onlyoffice/data:/var/www/onlyoffice/Data
      - ${DATA}/onlyoffice/logs:/var/log/onlyoffice
      - ${DATA}/onlyoffice/fonts:/usr/share/fonts/truetype/custom
    environment:
      JWT_ENABLED: "true"
      JWT_SECRET: \${ONLYOFFICE_JWT_SECRET}
    networks:
      - homelab-net

# =============================================================
#  NETWORKS & VOLUMES
# =============================================================
networks:
  homelab-net:
    driver: bridge
  seafile-net:
    driver: bridge
  immich-net:
    driver: bridge
  joplin-net:
    driver: bridge
  paperless-net:
    driver: bridge

volumes:
  immich-ml-cache:
COMPOSE

log "docker-compose.yml created"

# =============================================================================
#  6. START SERVICES
# =============================================================================
step "6. Starting services"
cd "$HOMELAB"
docker compose --env-file .env up -d --remove-orphans
log "All services started"

# =============================================================================
#  7. SUMMARY
# =============================================================================
step "7. Summary"
echo ""
echo -e "${BOLD}+----------------------------------------------------------+${NC}"
echo -e "${BOLD}|           HomeServer -- Installed Services               |${NC}"
echo -e "${BOLD}+----------------------------------------------------------+${NC}"
printf "| %-14s  https://%-31s|\n" "Webmin"        "${SERVER_IP}:10000"
printf "| %-14s  http://%-32s|\n" "Seafile"       "${SERVER_IP}:8060"
printf "| %-14s  http://%-32s|\n" "BentoPDF"      "${SERVER_IP}:8061"
printf "| %-14s  http://%-32s|\n" "IT-Tools"      "${SERVER_IP}:8062"
printf "| %-14s  http://%-32s|\n" "FreshRSS"      "${SERVER_IP}:8063"
printf "| %-14s  http://%-32s|\n" "Immich"        "${SERVER_IP}:8064"
printf "| %-14s  http://%-32s|\n" "Joplin Server" "${SERVER_IP}:8065"
printf "| %-14s  http://%-32s|\n" "Paperless-ngx" "${SERVER_IP}:8066"
printf "| %-14s  http://%-32s|\n" "n8n"           "${SERVER_IP}:8067"
printf "| %-14s  http://%-32s|\n" "OnlyOffice"    "${SERVER_IP}:8068"
echo -e "${BOLD}+----------------------------------------------------------+${NC}"
echo -e "| Seafile login:  me@mail.com  /  admin                    |"
echo -e "| .env:           ${HOMELAB}/.env                   |"
echo -e "| Compose:        ${HOMELAB}/docker-compose.yml     |"
echo -e "| Data:           ${DATA}/                |"
echo -e "| Shared dir:     ${SHARED}/                        |"
echo -e "${BOLD}+----------------------------------------------------------+${NC}"
echo ""
warn "Seafile and Immich need 1-2 minutes to initialize before they are accessible."
warn ".env contains secrets -- secure the file and do not commit it to git."
echo ""
log "Installation complete."
