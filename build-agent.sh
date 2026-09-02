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
    cp -r packages/debs/SPECS/unishield-agent/debian ./debian
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
    for deb in ../unishield-agent_*.deb ./unishield-agent_*.deb "$(dirname "$PWD")"/unishield-agent_*.deb; do
        [ -f "$deb" ] && cp "$deb" "$OUTPUT_DIR/" && echo "  copied: $deb"
    done
    rm -rf debian gen_permissions.sh
    echo ""
    ls -la "$OUTPUT_DIR/"*.deb 2>/dev/null && echo "DONE: see $OUTPUT_DIR/"
}

build_rpm() {
    echo "[0/4] Baking manager config into RPM spec..."
    if [ -z "$MANAGER_IP" ] || [ "$MANAGER_IP" = "0.0.0.0" ]; then
        echo "ERROR: MANAGER_IP not set in customer.conf"
        exit 1
    fi
    SPEC=packages/rpms/SPECS/unishield-agent.spec
    # Bake manager IP into the spec so install.sh writes it into ossec.conf
    sed -i "s/USER_AGENT_SERVER_IP=\"MANAGER_IP\"/USER_AGENT_SERVER_IP=\"${MANAGER_IP}\"/" "$SPEC"
    echo "  spec -> server IP=${MANAGER_IP}"

    echo "[1/4] Preparing RPM source tree..."
    rm -rf rpmbuild
    mkdir -p rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
    cp "$SPEC" rpmbuild/SPECS/unishield-agent.spec
    # Package source as unishield-agent-<ver> tar (rpmbuild needs SOURCES/<name>-<version>.tar.gz)
    tar czf rpmbuild/SOURCES/unishield-agent-${VERSION}.tar.gz --transform="s/^/unishield-agent-${VERSION}\//" \
        --exclude=.git --exclude=build-output --exclude=rpmbuild -C . . 2>/dev/null

    echo "[2/4] Building agent binaries..."
    make -C src deps TARGET=agent 2>&1 | tail -2
    make -C src TARGET=agent -j2 2>&1 | tail -3

    echo "[3/4] Running rpmbuild..."
    HASHCOMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "0000000")
    rpmbuild --nodeps --define "_buildshell /bin/bash" --define "_topdir $(pwd)/rpmbuild" \
        --define "_version ${VERSION}" \
        --define "_release ${REVISION}" \
        --define "_hashcommit ${HASHCOMMIT}" \
        --define '_isstage "no"' \
        --define "_debugenabled yes" \
        --define "_threads 2" \
        -bb rpmbuild/SPECS/unishield-agent.spec 2>&1 | tail -8

    echo "[4/4] Collecting RPM..."
    mkdir -p "$OUTPUT_DIR"
    for rpm in rpmbuild/RPMS/x86_64/unishield-agent-*.rpm rpmbuild/RPMS/*/unishield-agent-*.rpm; do
        [ -f "$rpm" ] && cp -f "$rpm" "$OUTPUT_DIR/" && echo "  copied: $rpm"
    done
    rm -rf rpmbuild
    echo ""
    ls -la "$OUTPUT_DIR/"*.rpm 2>/dev/null && echo "DONE: see $OUTPUT_DIR/"
}

build_win() {
    echo "[0/4] Baking manager config into installer (GPO-ready)..."
    # Bake MANAGER_IP / MANAGER_PORT / PROTOCOL from customer.conf into the
    # ossec.conf template so the resulting .exe is pre-configured. No env vars
    # or per-endpoint setup needed - GPO can just push the same exe everywhere.
    if [ -z "$MANAGER_IP" ] || [ "$MANAGER_IP" = "0.0.0.0" ]; then
        echo "ERROR: MANAGER_IP not set in customer.conf"
        exit 1
    fi
    sed -i "s|<address>[^<]*</address>|<address>${MANAGER_IP}</address>|" src/win32/ossec.conf
    sed -i "s|<port>[0-9]*</port>|<port>${MANAGER_PORT:-1514}</port>|" src/win32/ossec.conf
    sed -i "s|<protocol>[^<]*</protocol>|<protocol>${PROTOCOL:-tcp}</protocol>|" src/win32/ossec.conf
    echo "  ossec.conf template -> address=$MANAGER_IP port=${MANAGER_PORT:-1514} protocol=${PROTOCOL:-tcp}"

    echo "[1/4] Building Windows agent (mingw + nsis)..."
    # Clean stale artifacts from a prior Linux (TARGET=agent) build in this
    # shared source tree - Linux-format .o/.so files break the mingw link.
    echo "  Cleaning stale Linux build artifacts..."
    find src -name '*.o' -delete 2>/dev/null
    find src -path '*/build/CMakeCache.txt' -delete 2>/dev/null
    make -C src deps TARGET=winagent > /tmp/win-deps.log 2>&1 || { echo "ERROR: winagent deps build failed:"; tail -20 /tmp/win-deps.log; exit 1; }
    make -C src TARGET=winagent -j2 > /tmp/win-build.log 2>&1 || { echo "ERROR: winagent build failed:"; tail -20 /tmp/win-build.log; exit 1; }

    echo "[2/4] Collecting Windows artifacts..."
    mkdir -p "$OUTPUT_DIR"
    # Copy the built binaries and installer to the output directory
    find src/win32 -maxdepth 1 \( -name '*.exe' -o -name '*.dll' -o -name '*.sys' \) -exec cp -f {} "$OUTPUT_DIR/" \; 2>/dev/null || true

    echo "[3/4] Copying installer..."
    for exe in src/win32/unishield-agent-*.exe src/win32/wazuh-agent-*.exe; do
        [ -f "$exe" ] && cp -f "$exe" "$OUTPUT_DIR/" && echo "  copied: $exe"
    done

    echo "[4/4] Verifying baked IP..."
    grep -A3 "<client>" src/win32/ossec.conf | grep "<address>" || echo "  (check manually)"
    echo ""
    ls -la "$OUTPUT_DIR/"*.exe 2>/dev/null && echo "DONE: see $OUTPUT_DIR/"
}

build_macos() {
    echo "[1/3] Preparing macOS package builder..."
    echo "  NOTE: macOS .pkg builds require a Mac with munkipkg + a code-signing cert."
    echo "  This script prepares the whitelabeled source; run on a Mac:"
    echo "    packages/macos/generate_wazuh_packages.sh -b ${BRANCH:-main} -v ${VERSION} -r ${REVISION} -a x86_64"
    echo ""

    echo "[2/3] Verifying whitelabel files..."
    grep -q "Unishield 360" packages/macos/package_files/introduction.txt && echo "  introduction.txt: branded OK"
    grep -q "unishield360" packages/macos/specs/build-info.json && echo "  build-info.json: branded OK"
    grep -q "unishield" packages/macos/generate_wazuh_packages.sh && echo "  generate script: branded OK"

    echo "[3/3] macOS prep complete. Build on a Mac to produce .pkg."
    echo ""
}

case "${1:-deb}" in
    deb) build_deb ;;
    rpm) build_rpm ;;
    win) build_win ;;
    macos) build_macos ;;
    *)   echo "Usage: ./build-agent.sh [deb|rpm|win|macos]"; exit 1 ;;
esac
