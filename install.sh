#!/usr/bin/env bash
# Plus Collection — one-shot installer for PasarGuard / Marzban / Marzneshin
#
# Examples:
#   curl -fsSL https://raw.githubusercontent.com/mmaddeveloper/subforme/main/install.sh | sudo bash
#   sudo bash install.sh                        # interactive
#   sudo bash install.sh --no-bridge            # template only, skip the IP bridge
#   sudo bash install.sh --panel marzban
#   sudo bash install.sh --admin USER --pass PASS --panel-url http://127.0.0.1:8000

# Everything below runs inside _subforme_main so that when invoked via
# `curl | sudo bash`, bash buffers the *entire* function body before it
# starts executing it. Otherwise our later `exec 0</dev/tty` would
# redirect bash's stdin (which IS the script being piped in), and bash
# would lose the rest of the script — the visible symptom is the banner
# printing and then the process appearing to hang.

_subforme_main() {

set -euo pipefail

# First thing: prove we started — so users piping via `curl | sudo bash` see
# *something* immediately even if a later step fails silently.
echo "==> subforme installer — starting" >&2

# When piped via `curl | bash`, stdin is the script — `read` would consume
# script bytes instead of typed input. Re-attach stdin to the real terminal.
# Wrap in `|| true` so a non-readable /dev/tty (no controlling terminal, some
# CI/SSH configs) doesn't kill the whole script under set -e. We'll only need
# stdin if credentials weren't passed via flags.
if [ ! -t 0 ] && [ -r /dev/tty ]; then
    exec 0</dev/tty 2>/dev/null || echo "    (note: couldn't reattach to /dev/tty — pass --admin USER --pass PASS to run non-interactively)" >&2
fi

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
            cat <<'HELP'
Plus Collection installer — PasarGuard / Marzban / Marzneshin

  curl -fsSL https://raw.githubusercontent.com/mmaddeveloper/subforme/main/install.sh | sudo bash
  sudo bash install.sh                              # interactive
  sudo bash install.sh --no-bridge                  # template only
  sudo bash install.sh --panel marzban
  sudo bash install.sh --admin USER --pass PASS     # non-interactive
  sudo bash install.sh --panel-url http://127.0.0.1:8000
HELP
            exit 0 ;;
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

# Download helper — uses curl if available (the same binary that piped this
# script), else falls back to wget. Temp file lives in the destination
# directory so the final `mv` is atomic (rename within the same FS); /tmp
# may be a separate tmpfs on some distros, which would degrade mv to a
# non-atomic copy+unlink and let the panel briefly see a partial template.
download() {
    local url="$1" out="$2" tmp dest_dir status
    dest_dir="$(dirname "$out")"
    mkdir -p "$dest_dir"
    tmp="$(mktemp "$dest_dir/.subforme.XXXXXX")" || return 1
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 2 --max-time 60 "$url" -o "$tmp" || { rm -f "$tmp"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        # `--server-response` would print headers; we just want the exit code
        # to reflect HTTP errors. `wget` defaults to leaving 4xx/5xx bodies
        # on disk — `-q --tries=2 --timeout=60` with explicit status check.
        if ! wget -q --tries=2 --timeout=60 -O "$tmp" "$url"; then
            rm -f "$tmp"; return 1
        fi
    else
        echo "✗ need curl or wget" >&2; rm -f "$tmp"; return 1
    fi
    [ -s "$tmp" ] || { echo "✗ downloaded $url is empty" >&2; rm -f "$tmp"; return 1; }
    mv "$tmp" "$out"
}

# Reject password characters that systemd's EnvironmentFile parser can't
# round-trip: leading whitespace is stripped, `#` starts a comment, raw
# newlines split the value. Returns 0 if safe, prints reason and 1 otherwise.
validate_env_value() {
    local label="$1" value="$2"
    case "$value" in
        " "*|"	"*)
            echo "✗ $label cannot start with whitespace (systemd strips it)" >&2; return 1 ;;
        *"#"*)
            echo "✗ $label contains '#' which systemd treats as a comment — please change the panel admin password" >&2; return 1 ;;
        *$'\n'*|*$'\r'*)
            echo "✗ $label contains a newline — please change the panel admin password" >&2; return 1 ;;
    esac
    return 0
}

# -------------------- 1) template --------------------
mkdir -p "$TEMPLATE_DIR"
download "$RELEASE_LATEST/index.html" "$TEMPLATE_DIR/index.html"
echo "    ✓ template downloaded"

# -------------------- 2) panel .env --------------------
touch "$ENV_FILE"
if grep -q '^CUSTOM_TEMPLATES_DIRECTORY' "$ENV_FILE"; then
    EXISTING_DIR=$(sed -n 's/^CUSTOM_TEMPLATES_DIRECTORY=//p' "$ENV_FILE" | head -1 | sed 's/^"//;s/"$//')
    if [ "$EXISTING_DIR" != "$TEMPLATE_BASE" ]; then
        echo "    ⚠ CUSTOM_TEMPLATES_DIRECTORY is already $EXISTING_DIR — leaving it. If the panel doesn't pick up the new template, change it to $TEMPLATE_BASE manually" >&2
    fi
else
    echo "CUSTOM_TEMPLATES_DIRECTORY=\"$TEMPLATE_BASE\"" >> "$ENV_FILE"
fi
grep -q '^SUBSCRIPTION_PAGE_TEMPLATE' "$ENV_FILE" || echo 'SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"' >> "$ENV_FILE"
# When the panel sits behind nginx (which is how it's typically deployed,
# and how the bridge is exposed via /sub-online/ too), uvicorn's default
# ProxyHeaders=False makes request.client.host the loopback peer (127.0.0.1)
# for every visitor — so user_subscription_updates.ip ends up as 127.0.0.1
# for everyone, and the "Connected IPs" section becomes useless. Turn on
# X-Forwarded-For trust. Default forwarded_allow_ips already restricts this
# to 127.0.0.1, which is correct for nginx-on-same-host setups.
grep -q '^UVICORN_PROXY_HEADERS' "$ENV_FILE" || echo 'UVICORN_PROXY_HEADERS=true' >> "$ENV_FILE"
echo "    ✓ panel .env configured (incl. UVICORN_PROXY_HEADERS=true for real client IPs)"

# -------------------- 3) bridge --------------------
if [ "$INSTALL_BRIDGE" = "true" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
        echo "✗ python3 not found — skip bridge with --no-bridge or install python3" >&2; exit 1
    fi

    # Reuse credentials from a prior install so re-running the script is
    # silent (true update). Flags (--admin / --pass) still override.
    if [ -f "$BRIDGE_DIR/.env" ]; then
        OLD_USER=$(sed -n 's/^PG_ADMIN_USER=//p' "$BRIDGE_DIR/.env")
        OLD_PASS=$(sed -n 's/^PG_ADMIN_PASS=//p' "$BRIDGE_DIR/.env")
        OLD_PURL=$(sed -n 's/^PANEL_URL=//p'     "$BRIDGE_DIR/.env")
        [ -z "$ADMIN_USER" ] && ADMIN_USER="$OLD_USER"
        [ -z "$ADMIN_PASS" ] && ADMIN_PASS="$OLD_PASS"
        [ "$PANEL_URL" = "http://127.0.0.1:8000" ] && [ -n "$OLD_PURL" ] && PANEL_URL="$OLD_PURL"
        echo "    ✓ reusing existing bridge credentials"
    fi

    if [ -z "$ADMIN_USER" ]; then read -rp "panel admin username: " ADMIN_USER; fi
    if [ -z "$ADMIN_PASS" ]; then read -rsp "panel admin password: " ADMIN_PASS; echo; fi
    [ -z "$ADMIN_USER" ] && { echo "✗ admin username is required (--admin USER)" >&2; exit 1; }
    [ -z "$ADMIN_PASS" ] && { echo "✗ admin password is required (--pass PASS)" >&2; exit 1; }
    validate_env_value "admin username" "$ADMIN_USER" || exit 1
    validate_env_value "admin password" "$ADMIN_PASS" || exit 1

    mkdir -p "$BRIDGE_DIR"
    echo "    ↻ downloading bridge service..."
    # Try the release asset first (served from GitHub's release CDN, which is
    # usually reachable even where raw.githubusercontent.com is throttled);
    # fall back to the raw URL on main if the release lookup fails.
    if ! download "$RELEASE_LATEST/bridge.py" "$BRIDGE_DIR/bridge.py" \
       && ! download "$REPO_RAW/bridge/bridge.py" "$BRIDGE_DIR/bridge.py"; then
        echo "✗ couldn't download bridge.py — both the release asset and raw URL failed" >&2
        echo "    try manually: curl -fsSL $RELEASE_LATEST/bridge.py -o $BRIDGE_DIR/bridge.py" >&2
        exit 1
    fi
    chmod +x "$BRIDGE_DIR/bridge.py"
    echo "    ✓ bridge service downloaded"

    # Write .env with printf so values containing $, `, \, " survive intact
    # (heredoc would expand them). umask makes the file root-only.
    umask 077
    : > "$BRIDGE_DIR/.env"
    printf 'PANEL_URL=%s\n'     "$PANEL_URL"   >> "$BRIDGE_DIR/.env"
    printf 'PG_ADMIN_USER=%s\n' "$ADMIN_USER"  >> "$BRIDGE_DIR/.env"
    printf 'PG_ADMIN_PASS=%s\n' "$ADMIN_PASS"  >> "$BRIDGE_DIR/.env"
    printf 'PORT=%s\n'          "$BRIDGE_PORT" >> "$BRIDGE_DIR/.env"
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
# Hardening — bridge only does outbound HTTP, nothing else
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$BRIDGE_DIR
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true

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

    # Patch ONLINE_IPS_ENDPOINT in the freshly-downloaded template. Three
    # possible states: unset (empty string in template), already set to our
    # value (re-run / update), or set to something else (custom edit).
    if grep -q "const ONLINE_IPS_ENDPOINT = '/sub-online/{token}';" "$TEMPLATE_DIR/index.html"; then
        echo "    ✓ template ONLINE_IPS_ENDPOINT already wired to bridge"
    elif grep -q "const ONLINE_IPS_ENDPOINT = '';" "$TEMPLATE_DIR/index.html"; then
        sed -i.bak "s|const ONLINE_IPS_ENDPOINT = '';|const ONLINE_IPS_ENDPOINT = '/sub-online/{token}';|" "$TEMPLATE_DIR/index.html"
        rm -f "$TEMPLATE_DIR/index.html.bak"
        echo "    ✓ template ONLINE_IPS_ENDPOINT set to /sub-online/{token}"
    else
        echo "    ⚠ couldn't find the ONLINE_IPS_ENDPOINT marker in the template — the live-IPs feature won't work until you edit it manually" >&2
        echo "    ⚠ open $TEMPLATE_DIR/index.html and set: const ONLINE_IPS_ENDPOINT = '/sub-online/{token}';" >&2
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
# Exit from inside the function so that, when invoked via `curl | bash`,
# bash never tries to read further commands after the function returns
# from a stdin that was redirected to /dev/tty mid-script.
exit 0

}  # end _subforme_main

_subforme_main "$@"
