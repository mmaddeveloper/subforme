#!/usr/bin/env bash
# Plus Collection — uninstaller for PasarGuard / Marzban / Marzneshin
#
# Reverses everything install.sh did:
#   1. stop + disable + remove the subforme-bridge systemd service
#   2. remove /opt/subforme-bridge (binary + .env)
#   3. remove the installed index.html from the panel's template dir
#   4. strip the three lines install.sh added to the panel's .env
#      (CUSTOM_TEMPLATES_DIRECTORY, SUBSCRIPTION_PAGE_TEMPLATE,
#      UVICORN_PROXY_HEADERS)
#   5. print the nginx snippet to remove manually
#   6. restart the panel
#
# Idempotent — safe to re-run.
#
# Examples:
#   curl -fsSL https://raw.githubusercontent.com/mmaddeveloper/subforme/main/uninstall.sh | sudo bash
#   sudo bash uninstall.sh                       # interactive confirm
#   sudo bash uninstall.sh --yes                 # no prompt
#   sudo bash uninstall.sh --panel marzban
#   sudo bash uninstall.sh --keep-env            # leave panel .env untouched
#   sudo bash uninstall.sh --keep-template       # leave the index.html file

# (function-wrap for curl|bash safety — see install.sh for the rationale)
_subforme_uninstall_main() {

set -euo pipefail

echo "==> subforme uninstaller — starting" >&2

# Reattach stdin to /dev/tty when piped via curl|bash, so the confirm prompt
# reads from the terminal instead of consuming the rest of the script body.
if [ ! -t 0 ] && [ -r /dev/tty ]; then
    exec 0</dev/tty 2>/dev/null || echo "    (note: couldn't reattach to /dev/tty — pass --yes to skip the confirm)" >&2
fi

PANEL="${PANEL:-pasarguard}"
YES=false
KEEP_ENV=false
KEEP_TEMPLATE=false
BRIDGE_DIR="/opt/subforme-bridge"

while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y)       YES=true; shift ;;
        --panel)        PANEL="$2"; shift 2 ;;
        --keep-env)     KEEP_ENV=true; shift ;;
        --keep-template) KEEP_TEMPLATE=true; shift ;;
        -h|--help)
            cat <<'HELP'
Plus Collection uninstaller — PasarGuard / Marzban / Marzneshin

  curl -fsSL https://raw.githubusercontent.com/mmaddeveloper/subforme/main/uninstall.sh | sudo bash
  sudo bash uninstall.sh                       # interactive
  sudo bash uninstall.sh --yes                 # no prompt
  sudo bash uninstall.sh --panel marzban
  sudo bash uninstall.sh --keep-env            # leave panel .env alone
  sudo bash uninstall.sh --keep-template       # leave index.html in place
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

echo "==> Plan:"
echo "    panel:       $PANEL"
[ "$KEEP_TEMPLATE" = false ] && echo "    will remove: $TEMPLATE_DIR/index.html"
[ "$KEEP_ENV" = false ]      && echo "    will edit:   $ENV_FILE (strip 3 lines)"
echo "    will remove: $BRIDGE_DIR/"
echo "    will remove: /etc/systemd/system/subforme-bridge.service"
echo "    will run:    $RESTART_CMD"
echo

if [ "$YES" != "true" ]; then
    read -rp "proceed? [y/N] " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "aborted."; exit 0 ;;
    esac
fi

# 1) bridge service
if systemctl list-unit-files subforme-bridge.service >/dev/null 2>&1; then
    systemctl stop subforme-bridge 2>/dev/null || true
    systemctl disable subforme-bridge >/dev/null 2>&1 || true
    echo "    ✓ bridge service stopped & disabled"
fi
if [ -f /etc/systemd/system/subforme-bridge.service ]; then
    rm -f /etc/systemd/system/subforme-bridge.service
    systemctl daemon-reload
    echo "    ✓ systemd unit removed"
fi

# 2) bridge directory
if [ -d "$BRIDGE_DIR" ]; then
    rm -rf "$BRIDGE_DIR"
    echo "    ✓ $BRIDGE_DIR removed"
fi

# 3) installed template
if [ "$KEEP_TEMPLATE" = false ] && [ -f "$TEMPLATE_DIR/index.html" ]; then
    rm -f "$TEMPLATE_DIR/index.html"
    echo "    ✓ template removed from $TEMPLATE_DIR"
    # Try to clean empty parent dirs we may have created; rmdir is no-op if non-empty.
    rmdir "$TEMPLATE_DIR" 2>/dev/null && echo "    ✓ empty $TEMPLATE_DIR cleaned up" || true
fi

# 4) panel .env — strip our three lines, leaving everything else intact
if [ "$KEEP_ENV" = false ] && [ -f "$ENV_FILE" ]; then
    # Use a temp file in the same directory for an atomic rename. Match the
    # exact KEY= form at the start of a line; do NOT touch keys that just
    # happen to share a prefix (e.g. CUSTOM_TEMPLATES_DIRECTORY_OLD).
    tmp="$(mktemp "$(dirname "$ENV_FILE")/.env.unsub.XXXXXX")"
    grep -vE '^(CUSTOM_TEMPLATES_DIRECTORY|SUBSCRIPTION_PAGE_TEMPLATE|UVICORN_PROXY_HEADERS)=' "$ENV_FILE" > "$tmp" || true
    if cmp -s "$ENV_FILE" "$tmp"; then
        echo "    ✓ panel .env had no subforme lines to remove"
        rm -f "$tmp"
    else
        # Preserve original ownership/permissions
        chown --reference="$ENV_FILE" "$tmp" 2>/dev/null || true
        chmod --reference="$ENV_FILE" "$tmp" 2>/dev/null || true
        mv "$tmp" "$ENV_FILE"
        echo "    ✓ stripped subforme lines from $ENV_FILE"
    fi
fi

# 5) nginx — we can't touch the user's config safely; print the snippet
cat <<NGINX

==> Manual step: if you added the nginx snippet during install, remove it now:

    location /sub-online/ {
        proxy_pass http://127.0.0.1:8787/api/sub/online/;
        proxy_set_header Host \$host;
    }

    Then reload nginx: sudo nginx -s reload   (or: sudo systemctl reload nginx)

NGINX

# 6) restart the panel so it picks up the env changes
echo "==> Restarting panel: $RESTART_CMD"
$RESTART_CMD || echo "    (couldn't restart automatically — run '$RESTART_CMD' yourself)"

echo "==> Done. Plus Collection has been uninstalled."
exit 0

}  # end _subforme_uninstall_main

_subforme_uninstall_main "$@"
