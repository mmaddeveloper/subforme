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
# Helper for flags that take a required value. Guards against:
#   1. running off the end of $@ (no second arg) — would crash under `set -u`
#   2. swallowing the next flag as a value (`--admin --pass foo` would
#      otherwise leave ADMIN_USER='--pass')
_take_arg() {
    if [ $# -lt 2 ] || [ "${2:0:2}" = "--" ]; then
        echo "✗ $1 requires a value" >&2; exit 1
    fi
    printf '%s' "$2"
}
while [ $# -gt 0 ]; do
    case "$1" in
        --no-bridge)    INSTALL_BRIDGE=false; shift ;;
        --panel)        PANEL=$(_take_arg "$@"); shift 2 ;;
        --panel-url)    PANEL_URL=$(_take_arg "$@"); shift 2 ;;
        --admin)        ADMIN_USER=$(_take_arg "$@"); shift 2 ;;
        --pass)         ADMIN_PASS=$(_take_arg "$@"); shift 2 ;;
        --bridge-port)  BRIDGE_PORT=$(_take_arg "$@"); shift 2 ;;
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

# Parse the panel's .env to discover how it's actually deployed. Two common
# topologies:
#   A) nginx in front, panel on localhost (UVICORN_HOST=127.0.0.1, no SSL_*)
#   B) uvicorn binds publicly with its own TLS (UVICORN_HOST=0.0.0.0,
#      UVICORN_SSL_CERTFILE set) — this is PasarGuard 4.x's default
# The bridge needs different wiring in each case.
PANEL_UVICORN_HOST=""
PANEL_UVICORN_PORT=""
PANEL_SSL_CERT=""
PANEL_SSL_KEY=""
PANEL_HOSTNAME=""
PANEL_DIRECT_TLS=false
if [ -f "$ENV_FILE" ]; then
    # Pull a key's value out of the panel's .env. Handles:
    #   - optional whitespace around '='
    #   - matched outer single or double quotes (only strip them when paired)
    #   - trailing whitespace + CR (Windows line endings)
    # We deliberately do NOT do a blanket `tr -d` on quotes — a hostname like
    # `O'Brien` shouldn't lose its apostrophe.
    _strip() {
        sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "$ENV_FILE" \
            | head -1 \
            | sed -E 's/[[:space:]]+$//; s/\r$//; s/^"([^"]*)"$/\1/; s/^'\''([^'\'']*)'\''$/\1/'
    }
    PANEL_UVICORN_HOST=$(_strip UVICORN_HOST)
    PANEL_UVICORN_PORT=$(_strip UVICORN_PORT)
    PANEL_SSL_CERT=$(_strip UVICORN_SSL_CERTFILE)
    PANEL_SSL_KEY=$(_strip UVICORN_SSL_KEYFILE)
fi
if [ -n "$PANEL_SSL_CERT" ] && [ -f "$PANEL_SSL_CERT" ]; then
    PANEL_DIRECT_TLS=true
    # Pull the hostname from the cert path (e.g. /var/lib/pasarguard/certs/foo.example.com/fullchain.pem)
    PANEL_HOSTNAME=$(echo "$PANEL_SSL_CERT" | sed -n 's|.*/certs/\([^/]*\)/.*|\1|p')
    # Fallback: read CN from the cert itself
    if [ -z "$PANEL_HOSTNAME" ] && command -v openssl >/dev/null 2>&1; then
        PANEL_HOSTNAME=$(openssl x509 -in "$PANEL_SSL_CERT" -noout -subject 2>/dev/null \
            | sed 's/.*CN[[:space:]]*=[[:space:]]*//;s/[,/].*//' | tr -d ' ')
    fi
fi

# If --panel-url wasn't passed, build it from what we discovered so the
# bridge talks to the right place. In direct-TLS mode use the hostname
# (loopback would fail SSL cert verification); otherwise loopback HTTP.
if [ "$PANEL_URL" = "http://127.0.0.1:8000" ]; then
    if [ "$PANEL_DIRECT_TLS" = "true" ] && [ -n "$PANEL_HOSTNAME" ] && [ -n "$PANEL_UVICORN_PORT" ]; then
        PANEL_URL="https://$PANEL_HOSTNAME:$PANEL_UVICORN_PORT"
    elif [ -n "$PANEL_UVICORN_PORT" ]; then
        PANEL_URL="http://127.0.0.1:$PANEL_UVICORN_PORT"
    fi
fi

# Direct-TLS panels can't accept a /sub-online/ same-origin route (uvicorn
# doesn't proxy and there's no nginx). Expose the bridge on its own public
# port using the same cert; the template uses an absolute URL.
BRIDGE_TLS=false
BRIDGE_BIND="127.0.0.1"
if [ "$PANEL_DIRECT_TLS" = "true" ] && [ -n "$PANEL_SSL_KEY" ] && [ -f "$PANEL_SSL_KEY" ] && [ -n "$PANEL_HOSTNAME" ]; then
    BRIDGE_TLS=true
    BRIDGE_BIND="0.0.0.0"
    [ "$BRIDGE_PORT" = "8787" ] && BRIDGE_PORT="8443"
    ENDPOINT_URL="https://$PANEL_HOSTNAME:$BRIDGE_PORT/api/sub/online/{token}"
    ECHARTS_URL="https://$PANEL_HOSTNAME:$BRIDGE_PORT/static/echarts.min.js"
    # Only set Origin when we actually have a port to attach to it —
    # `https://host:` would be a malformed origin and break every CORS check.
    if [ -n "$PANEL_UVICORN_PORT" ]; then
        ALLOWED_ORIGIN_VAL="https://$PANEL_HOSTNAME:$PANEL_UVICORN_PORT"
    else
        ALLOWED_ORIGIN_VAL="https://$PANEL_HOSTNAME"
    fi
elif [ "$PANEL_DIRECT_TLS" = "true" ]; then
    # Direct TLS detected but we couldn't piece together the hostname (cert
    # path didn't match the standard layout and openssl wasn't available).
    # Warn loudly — falling back to nginx-mode would silently 404 every
    # /sub-online/ request.
    echo "    ⚠ direct-TLS panel detected but couldn't extract hostname from $PANEL_SSL_CERT" >&2
    echo "    ⚠ install openssl or rename the cert dir to .../certs/<host>/fullchain.pem then re-run" >&2
    ENDPOINT_URL="/sub-online/{token}"
    ECHARTS_URL="/sub-online/static/echarts.min.js"
    ALLOWED_ORIGIN_VAL=""
else
    ENDPOINT_URL="/sub-online/{token}"
    # nginx-fronted setups need a second proxy_pass block for /sub-static/
    # → bridge's /static/. The installer prints it in the final hint.
    ECHARTS_URL="/sub-static/echarts.min.js"
    ALLOWED_ORIGIN_VAL=""
fi

echo "==> Plus Collection installer"
echo "    panel:      $PANEL"
echo "    templates:  $TEMPLATE_DIR"
echo "    panel env:  $ENV_FILE"
echo "    panel URL:  $PANEL_URL  ($([ "$PANEL_DIRECT_TLS" = true ] && echo "direct TLS detected" || echo "behind reverse proxy"))"
if [ "$INSTALL_BRIDGE" = "true" ]; then
    if [ "$BRIDGE_TLS" = true ]; then
        echo "    bridge:     yes — https://$BRIDGE_BIND:$BRIDGE_PORT (TLS via panel cert)"
        echo "    template:   $ENDPOINT_URL"
    else
        echo "    bridge:     yes — http://$BRIDGE_BIND:$BRIDGE_PORT (same-origin via nginx)"
        echo "    template:   $ENDPOINT_URL"
    fi
else
    echo "    bridge:     no"
fi
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
# Prefer the release asset (served from GitHub's release CDN, usually
# reachable even where raw.githubusercontent.com is throttled); fall back
# to the raw URL on main if the release lookup fails — same pattern as the
# bridge download below, so a missing/empty release asset doesn't hard-fail.
mkdir -p "$TEMPLATE_DIR"
if ! download "$RELEASE_LATEST/index.html" "$TEMPLATE_DIR/index.html" \
   && ! download "$REPO_RAW/index.html" "$TEMPLATE_DIR/index.html"; then
    echo "✗ couldn't download index.html — both the release asset and raw URL failed" >&2
    echo "    try manually: curl -fsSL $REPO_RAW/index.html -o $TEMPLATE_DIR/index.html" >&2
    exit 1
fi
echo "    ✓ template downloaded"

# -------------------- 2) panel .env --------------------
touch "$ENV_FILE"
if grep -qE '^CUSTOM_TEMPLATES_DIRECTORY[[:space:]]*=' "$ENV_FILE"; then
    EXISTING_DIR=$(sed -n 's/^CUSTOM_TEMPLATES_DIRECTORY=//p' "$ENV_FILE" | head -1 | sed 's/^"//;s/"$//')
    if [ "$EXISTING_DIR" != "$TEMPLATE_BASE" ]; then
        echo "    ⚠ CUSTOM_TEMPLATES_DIRECTORY is already $EXISTING_DIR — leaving it. If the panel doesn't pick up the new template, change it to $TEMPLATE_BASE manually" >&2
    fi
else
    echo "CUSTOM_TEMPLATES_DIRECTORY=\"$TEMPLATE_BASE\"" >> "$ENV_FILE"
fi
grep -qE '^SUBSCRIPTION_PAGE_TEMPLATE[[:space:]]*=' "$ENV_FILE" || echo 'SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"' >> "$ENV_FILE"
# When the panel sits behind nginx (which is how it's typically deployed,
# and how the bridge is exposed via /sub-online/ too), uvicorn's default
# ProxyHeaders=False makes request.client.host the loopback peer (127.0.0.1)
# for every visitor — so user_subscription_updates.ip ends up as 127.0.0.1
# for everyone, and the "Connected IPs" section becomes useless. Turn on
# X-Forwarded-For trust. Default forwarded_allow_ips already restricts this
# to 127.0.0.1, which is correct for nginx-on-same-host setups.
grep -qE '^UVICORN_PROXY_HEADERS[[:space:]]*=' "$ENV_FILE" || echo 'UVICORN_PROXY_HEADERS=true' >> "$ENV_FILE"
echo "    ✓ panel .env configured (incl. UVICORN_PROXY_HEADERS=true for real client IPs)"

# -------------------- 3) bridge --------------------
if [ "$INSTALL_BRIDGE" = "true" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
        echo "✗ python3 not found — skip bridge with --no-bridge or install python3" >&2; exit 1
    fi

    # Reuse credentials from a prior install so re-running the script is
    # silent (true update). Flags (--admin / --pass) still override. Detect
    # a corrupted .env (e.g. from a previous half-installed run where a
    # heredoc consumed part of the install.sh body into the password slot)
    # and refuse to reuse it.
    if [ -f "$BRIDGE_DIR/.env" ]; then
        OLD_USER=$(sed -n 's/^PG_ADMIN_USER=//p' "$BRIDGE_DIR/.env" | head -1)
        OLD_PASS=$(sed -n 's/^PG_ADMIN_PASS=//p' "$BRIDGE_DIR/.env" | head -1)
        OLD_PURL=$(sed -n 's/^PANEL_URL=//p'     "$BRIDGE_DIR/.env" | head -1)
        if [ -z "$OLD_USER" ] || [ -z "$OLD_PASS" ] \
           || ! validate_env_value "stored admin username" "$OLD_USER" 2>/dev/null \
           || ! validate_env_value "stored admin password" "$OLD_PASS" 2>/dev/null; then
            echo "    ⚠ existing $BRIDGE_DIR/.env is missing or corrupted — ignoring it" >&2
            rm -f "$BRIDGE_DIR/.env"
        else
            [ -z "$ADMIN_USER" ] && ADMIN_USER="$OLD_USER"
            [ -z "$ADMIN_PASS" ] && ADMIN_PASS="$OLD_PASS"
            [ "$PANEL_URL" = "http://127.0.0.1:8000" ] && [ -n "$OLD_PURL" ] && PANEL_URL="$OLD_PURL"
            echo "    ✓ reusing existing bridge credentials"
        fi
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

    # The template renders charts via ECharts. We serve the library from the
    # bridge so users never depend on an external CDN. Use the FULL build —
    # echarts.simple doesn't include `gauge` and we need it for the
    # data-limit ring. ~1MB, cached immutable after first load.
    mkdir -p "$BRIDGE_DIR/static"
    ECHARTS_VERSION="${ECHARTS_VERSION:-5.5.1}"
    ECHARTS_TAG_FILE="$BRIDGE_DIR/static/.echarts-tag"
    EXPECTED_TAG="echarts-full-$ECHARTS_VERSION"
    CURRENT_TAG=""
    [ -f "$ECHARTS_TAG_FILE" ] && CURRENT_TAG=$(cat "$ECHARTS_TAG_FILE")
    if [ "$CURRENT_TAG" != "$EXPECTED_TAG" ] || [ ! -s "$BRIDGE_DIR/static/echarts.min.js" ]; then
        echo "    ↻ downloading echarts v$ECHARTS_VERSION (full build)..."
        if download "https://cdn.jsdelivr.net/npm/echarts@$ECHARTS_VERSION/dist/echarts.min.js" "$BRIDGE_DIR/static/echarts.min.js"; then
            echo "$EXPECTED_TAG" > "$ECHARTS_TAG_FILE"
            echo "    ✓ ECharts installed ($(du -h "$BRIDGE_DIR/static/echarts.min.js" | cut -f1))"
        else
            echo "    ⚠ couldn't fetch ECharts — chart sections will degrade until you grab it manually:" >&2
            echo "    curl -fsSL https://cdn.jsdelivr.net/npm/echarts@$ECHARTS_VERSION/dist/echarts.min.js -o $BRIDGE_DIR/static/echarts.min.js" >&2
        fi
    fi

    # Older installs (pre-fe9752a) downloaded custom-gauge-panel.png next
    # to echarts.min.js for the original image-clipped gauge. The gauge is
    # now drawn from theme-colored shapes, so the image is dead weight —
    # remove it on upgrade to keep the static dir tidy.
    rm -f "$BRIDGE_DIR/static/custom-gauge-panel.png"

    # Rewrite .env from scratch — never just append, so re-runs converge to
    # the right state instead of stacking stale settings. printf %s keeps
    # values containing $, `, \, " intact (heredoc would shell-expand them).
    umask 077
    {
        printf 'PANEL_URL=%s\n'     "$PANEL_URL"
        printf 'PG_ADMIN_USER=%s\n' "$ADMIN_USER"
        printf 'PG_ADMIN_PASS=%s\n' "$ADMIN_PASS"
        printf 'PORT=%s\n'          "$BRIDGE_PORT"
        printf 'BIND_HOST=%s\n'     "$BRIDGE_BIND"
        printf 'STATIC_DIR=%s\n'    "$BRIDGE_DIR/static"
        if [ "$BRIDGE_TLS" = "true" ]; then
            printf 'TLS_CERT_FILE=%s\n' "$PANEL_SSL_CERT"
            printf 'TLS_KEY_FILE=%s\n'  "$PANEL_SSL_KEY"
        fi
        if [ -n "$ALLOWED_ORIGIN_VAL" ]; then
            printf 'ALLOWED_ORIGIN=%s\n' "$ALLOWED_ORIGIN_VAL"
        fi
    } > "$BRIDGE_DIR/.env"
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
        SCHEME=$([ "$BRIDGE_TLS" = "true" ] && echo "https" || echo "http")
        echo "    ✓ bridge running on $SCHEME://$BRIDGE_BIND:$BRIDGE_PORT"
    else
        echo "    ✗ bridge failed to start — check: journalctl -u subforme-bridge -n 50"
    fi

    # Always set the template's ONLINE_IPS_ENDPOINT to the right value for
    # this install. The line uses single quotes in the source, so the regex
    # accepts any current single-quoted value and replaces it in place. This
    # makes re-runs converge — moving between nginx-proxied and direct-TLS
    # modes works without manual edits.
    if grep -q "const ONLINE_IPS_ENDPOINT = '" "$TEMPLATE_DIR/index.html"; then
        # Escape the replacement value's `|`s and `&`s for sed
        ESC=$(printf '%s' "$ENDPOINT_URL" | sed 's/[\\&|]/\\&/g')
        sed -i.bak "s|const ONLINE_IPS_ENDPOINT = '[^']*';|const ONLINE_IPS_ENDPOINT = '$ESC';|" "$TEMPLATE_DIR/index.html"
        rm -f "$TEMPLATE_DIR/index.html.bak"
        echo "    ✓ template ONLINE_IPS_ENDPOINT -> $ENDPOINT_URL"
    else
        echo "    ⚠ ONLINE_IPS_ENDPOINT marker not found in $TEMPLATE_DIR/index.html — open it and set:" >&2
        echo "        const ONLINE_IPS_ENDPOINT = '$ENDPOINT_URL';" >&2
    fi

    # Same idea for the ECharts library URL (served by the bridge under
    # /static/echarts.min.js). Skip silently if the template hasn't been
    # updated to consume it yet — newer installs.sh, older index.html.
    if grep -q "const ECHARTS_URL = '" "$TEMPLATE_DIR/index.html"; then
        ESC=$(printf '%s' "$ECHARTS_URL" | sed 's/[\\&|]/\\&/g')
        sed -i.bak "s|const ECHARTS_URL = '[^']*';|const ECHARTS_URL = '$ESC';|" "$TEMPLATE_DIR/index.html"
        rm -f "$TEMPLATE_DIR/index.html.bak"
        echo "    ✓ template ECHARTS_URL    -> $ECHARTS_URL"
    fi

    if [ "$BRIDGE_TLS" = "true" ]; then
        # Bridge listens publicly with TLS; open the firewall best-effort.
        # Order: firewalld (Fedora/RHEL) -> ufw (Debian/Ubuntu) -> raw iptables.
        if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port="$BRIDGE_PORT"/tcp >/dev/null 2>&1 \
                && firewall-cmd --reload >/dev/null 2>&1 \
                && echo "    ✓ firewalld: $BRIDGE_PORT/tcp opened (permanent)"
        elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
            ufw allow "$BRIDGE_PORT"/tcp >/dev/null 2>&1 && echo "    ✓ ufw: $BRIDGE_PORT/tcp opened"
        elif command -v iptables >/dev/null 2>&1; then
            if ! iptables -C INPUT -p tcp --dport "$BRIDGE_PORT" -j ACCEPT 2>/dev/null; then
                iptables -A INPUT -p tcp --dport "$BRIDGE_PORT" -j ACCEPT 2>/dev/null \
                    && echo "    ✓ iptables: $BRIDGE_PORT/tcp ACCEPT rule added (note: not persisted across reboot)"
            else
                echo "    ✓ iptables: $BRIDGE_PORT/tcp already allowed"
            fi
        fi
        cat <<NOTE

==> All done. If you're on a cloud provider with a separate firewall (Hetzner,
    DigitalOcean, AWS), also open TCP port $BRIDGE_PORT in their dashboard.
    Subscription pages will fetch IPs from $ENDPOINT_URL automatically.

NOTE
    else
        cat <<NGINX

==> Final step (manual): expose the bridge same-origin via nginx.
    Add BOTH location blocks inside your panel's server { } block, then
    reload nginx (one for the IPs API, one for the ECharts library):

    location /sub-online/ {
        proxy_pass http://127.0.0.1:$BRIDGE_PORT/api/sub/online/;
        proxy_set_header Host \$host;
    }
    location /sub-static/ {
        proxy_pass http://127.0.0.1:$BRIDGE_PORT/static/;
        proxy_set_header Host \$host;
    }

NGINX
    fi
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
