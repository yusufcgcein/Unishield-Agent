#!/bin/bash
# ============================================================
#  Unishield 360 Agent - One-command builder
#
#  Usage:
#    ./build-agent.sh [deb|rpm|win] [MANAGER_IP]
#
#  Examples:
#    ./build-agent.sh deb                     # uses IP from customer.conf
#    ./build-agent.sh deb 203.0.113.10        # override IP for this build only
#    ./build-agent.sh rpm 198.51.100.5        # build rpm for another environment
#
#  Output appears in ./build-output/
# ============================================================
set -e

cd "$(dirname "$0")"
source ./customer.conf

# Optional: override MANAGER_IP from command line (2nd argument)
if [ -n "$2" ]; then
    MANAGER_IP="$2"
fi

OUTPUT_DIR="$(pwd)/build-output"
mkdir -p "$OUTPUT_DIR"

echo ""
echo "=============================================="
echo "  Unishield 360 Agent builder"
echo "  Manager IP : $MANAGER_IP"
echo "  Target     : ${1:-deb}"
echo "=============================================="
echo ""

# --- Sanity checks ---
if [ -z "$MANAGER_IP" ] || [ "$MANAGER_IP" = "0.0.0.0" ]; then
    echo "ERROR: MANAGER_IP is not set in customer.conf"
    exit 1
fi

build_deb() {
    echo "[1/3] Preparing debian packaging..."
    rm -rf debian
    cp -r packages/debs/SPECS/wazuh-agent/debian ./debian
    sed -i "s/4.14.7-RELEASE/${VERSION}-${REVISION}/" debian/changelog

    # Bake manager IP into package build (install.sh writes it into ossec.conf)
    sed -i "s/USER_AGENT_SERVER_IP=\"MANAGER_IP\"/USER_AGENT_SERVER_IP=\"${MANAGER_IP}\"/" debian/rules

    echo "[2/3] Building agent binaries..."
    make -C src deps TARGET=agent 2>&1 | tail -2
    make -C src TARGET=agent -j2 2>&1 | tail -3

    echo "[3/3] Building .deb package..."
    cp packages/debs/utils/gen_permissions.sh ./gen_permissions.sh 2>/dev/null || true
    debuild --rootcmd=sudo -b -uc -us 2>&1 | tail -5

    # debuild writes output one level above the build dir (repo parent)
    for deb in ../wazuh-agent_*.deb ./wazuh-agent_*.deb "$(dirname "$PWD")"/wazuh-agent_*.deb; do
        [ -f "$deb" ] && cp "$deb" "$OUTPUT_DIR/" && echo "  copied: $deb"
    done
    rm -rf debian gen_permissions.sh
    echo ""
    ls -la "$OUTPUT_DIR/"*.deb 2>/dev/null && echo "DONE: see $OUTPUT_DIR/"
}

build_rpm() {
    echo "RPM build not yet wired to one-command flow."
    echo "Use: ./packages/generate_package.sh --system rpm -t agent -a x86_64 --sources $(pwd)"
}

build_win() {
    echo "Windows build requires cross toolchain (mingw + nsis)."
    echo "cd src && make TARGET=winagent -j2"
}

case "${1:-deb}" in
    deb) build_deb ;;
    rpm) build_rpm ;;
    win) build_win ;;
    *)   echo "Usage: ./build-agent.sh [deb|rpm|win]"; exit 1 ;;
esac
