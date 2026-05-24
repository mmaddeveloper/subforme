#!/usr/bin/env bash
# Plus Collection — one-shot installer for PasarGuard / Marzban / Marzneshin
#
# Examples:
#   curl -fsSL https://raw.githubusercontent.com/mmaddeveloper/subforme/main/install.sh | sudo bash
#   sudo bash install.sh                        # interactive
#   sudo bash install.sh --no-bridge            # template only, skip the IP bridge
#   sudo bash install.sh --panel marzban
#   sudo bash install.sh --admin USER --pass PASS --panel-url http://127.0.0.1:8000

set -euo pipefail

# -------------------- defaults --------------------
PANEL="${PANEL:-pasarguard}"
PANEL_URL="${PANEL_URL:-http://127.0.0.1:8000}"
ADMIN_USER="${ADMIN_USER:-}"
ADMIN_PASS="${ADMIN_PASS:-}"
INSTALL_BRIDGE=true
BRIDGE_DIR="/opt/subforme-bridge"
BRIDGE_PORT="${BRIDGE_PORT:-8787}"
REPO_RAW="https://raw.githubusercontent.com/mmaddeveloper/subforme/main"
RELEASE_LATEST="https://github.com/mmaddeveloper/subforme/releases/latest/download"

# -------------------- args --------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --no-bridge)    INSTALL_BRIDGE=false; shift ;;
        --panel)        PANEL="$2"; shift 2 ;;
        --panel-url)    PANEL_URL="$2"; shift 2 ;;
        --admin)        ADMIN_USER="$2"; shift 2 ;;
        --pass)         ADMIN_PASS="$2"; shift 2 ;;
        --bridge-port)  BRIDGE_PORT="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "✗ run as root (use sudo)" >&2; exit 1
fi

case "$PANEL" in
    pasarguard) TEMPLATE_DIR=/var/lib/pasarguard/templates/subscription; ENV_FILE=/opt/pasarguard/.env;       RESTART_CMD="pasarguard restart" ;;
    marzban)    TEMPLATE_DIR=/var/lib/marzban/templates/subscription;    ENV_FILE=/opt/marzban/.env;          RESTART_CMD="marzban restart" ;;
    marzneshin) TEMPLATE_DIR=/var/lib/marzneshin/templates/subscription; ENV_FILE=/etc/opt/marzneshin/.env;   RESTART_CMD="marzneshin restart" ;;
    *) echo "✗ unknown panel: $PANEL (use pasarguard | marzban | marzneshin)" >&2; exit 1 ;;
esac
TEMPLATE_BASE="$(dirname "$TEMPLATE_DIR")/"

echo "==> Plus Collection installer"
echo "    panel:      $PANEL"
echo "    templates:  $TEMPLATE_DIR"
echo "    panel env:  $ENV_FILE"
echo "    bridge:     $([ "$INSTALL_BRIDGE" = true ] && echo "yes (port $BRIDGE_PORT)" || echo "no")"
echo

# -------------------- 1) template --------------------
mkdir -p "$TEMPLATE_DIR"
wget -qN -P "$TEMPLATE_DIR" "$RELEASE_LATEST/index.html"
echo "    ✓ template downloaded"

# -------------------- 2) panel .env --------------------
touch "$ENV_FILE"
grep -q '^CUSTOM_TEMPLATES_DIRECTORY' "$ENV_FILE" || echo "CUSTOM_TEMPLATES_DIRECTORY=\"$TEMPLATE_BASE\"" >> "$ENV_FILE"
grep -q '^SUBSCRIPTION_PAGE_TEMPLATE' "$ENV_FILE" || echo 'SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"' >> "$ENV_FILE"
echo "    ✓ panel .env configured"

# -------------------- 3) bridge --------------------
if [ "$INSTALL_BRIDGE" = "true" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
        echo "✗ python3 not found — skip bridge with --no-bridge or install python3" >&2; exit 1
    fi

    # Reuse credentials from a prior install so re-running the script is
    # silent (true update). Flags (--admin / --pass) still override.
    if [ -f "$BRIDGE_DIR/.env" ]; then
        # shellcheck disable=SC1091
        OLD_USER=$(grep -E '^PG_ADMIN_USER=' "$BRIDGE_DIR/.env" | cut -d= -f2-)
        OLD_PASS=$(grep -E '^PG_ADMIN_PASS=' "$BRIDGE_DIR/.env" | cut -d= -f2-)
        OLD_PURL=$(grep -E '^PANEL_URL='     "$BRIDGE_DIR/.env" | cut -d= -f2-)
        [ -z "$ADMIN_USER" ] && ADMIN_USER="$OLD_USER"
        [ -z "$ADMIN_PASS" ] && ADMIN_PASS="$OLD_PASS"
        [ "$PANEL_URL" = "http://127.0.0.1:8000" ] && [ -n "$OLD_PURL" ] && PANEL_URL="$OLD_PURL"
        echo "    ✓ reusing existing bridge credentials"
    fi

    if [ -z "$ADMIN_USER" ]; then read -rp "panel admin username: " ADMIN_USER; fi
    if [ -z "$ADMIN_PASS" ]; then read -rsp "panel admin password: " ADMIN_PASS; echo; fi

    mkdir -p "$BRIDGE_DIR"
    wget -qO "$BRIDGE_DIR/bridge.py" "$REPO_RAW/bridge/bridge.py"
    chmod +x "$BRIDGE_DIR/bridge.py"

    umask 077
    cat > "$BRIDGE_DIR/.env" <<EOF
PANEL_URL=$PANEL_URL
PG_ADMIN_USER=$ADMIN_USER
PG_ADMIN_PASS=$ADMIN_PASS
PORT=$BRIDGE_PORT
EOF
    umask 022

    cat > /etc/systemd/system/subforme-bridge.service <<EOF
[Unit]
Description=Subforme online-IPs bridge
After=network.target

[Service]
Type=simple
WorkingDirectory=$BRIDGE_DIR
EnvironmentFile=$BRIDGE_DIR/.env
ExecStart=/usr/bin/env python3 $BRIDGE_DIR/bridge.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable subforme-bridge >/dev/null 2>&1 || true
    systemctl restart subforme-bridge   # picks up bridge.py + .env changes on re-runs
    sleep 1
    if systemctl is-active --quiet subforme-bridge; then
        echo "    ✓ bridge running on 127.0.0.1:$BRIDGE_PORT"
    else
        echo "    ✗ bridge failed to start — check: journalctl -u subforme-bridge -n 50"
    fi

    # Patch ONLINE_IPS_ENDPOINT in the installed template
    if grep -q "const ONLINE_IPS_ENDPOINT = '';" "$TEMPLATE_DIR/index.html"; then
        sed -i.bak "s|const ONLINE_IPS_ENDPOINT = '';|const ONLINE_IPS_ENDPOINT = '/sub-online/{token}';|" "$TEMPLATE_DIR/index.html"
        rm -f "$TEMPLATE_DIR/index.html.bak"
        echo "    ✓ template ONLINE_IPS_ENDPOINT set to /sub-online/{token}"
    fi

    cat <<NGINX

==> Final step (manual): expose the bridge same-origin via nginx.
    Add inside your panel's server { } block, then reload nginx:

    location /sub-online/ {
        proxy_pass http://127.0.0.1:$BRIDGE_PORT/api/sub/online/;
        proxy_set_header Host \$host;
    }

NGINX
fi

# -------------------- 4) restart panel --------------------
echo "==> Restarting panel: $RESTART_CMD"
$RESTART_CMD || echo "    (couldn't restart automatically — run '$RESTART_CMD' yourself)"

echo "==> Done."
