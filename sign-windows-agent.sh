#!/bin/bash
# ============================================================
#  Unishield 360 - Windows agent code signing (cross-platform)
#
#  Signs all Windows agent binaries and the NSIS installer
#  using osslsigncode (works on Linux, macOS and Windows).
#  Optional: if no certificate is configured, the script
#  skips signing with a warning so builds do not fail.
#
#  Usage:
#    ./sign-windows-agent.sh <win32_build_dir>
#
#  Configuration (via environment or customer.conf):
#    UNISHIELD_CERT_FILE  - code signing certificate (PEM cert, or
#                           PKCS#12 .pfx/.p12 bundle)
#    UNISHIELD_CERT_KEY   - private key file (PEM). Ignored when
#                           using a .pfx/.p12.
#    UNISHIELD_CERT_PASS  - password for the .pfx/.p12, or for an
#                           encrypted PEM private key.
#    UNISHIELD_TIMESTAMP  - RFC3161 timestamp server URL
#                           (default: http://timestamp.digicert.com)
#    UNISHIELD_CA_NAME    - root CA name used by Wazuh's trust
#                           verification (default: DigiCert Assured ID Root CA)
# ============================================================
set -euo pipefail

BUILD_DIR="${1:-win32}"
TIMESTAMP_URL="${UNISHIELD_TIMESTAMP:-http://timestamp.digicert.com}"
CA_NAME="${UNISHIELD_CA_NAME:-DigiCert Assured ID Root CA}"
CERT_FILE="${UNISHIELD_CERT_FILE:-}"
CERT_KEY="${UNISHIELD_CERT_KEY:-}"
CERT_PASS="${UNISHIELD_CERT_PASS:-}"

cd "$(dirname "$0")"

# --- Optional signing: skip if no certificate configured ---
if [ -z "$CERT_FILE" ]; then
    echo ""
    echo "  [sign] No code-signing certificate configured (UNISHIELD_CERT_FILE is empty)."
    echo "  [sign] Windows binaries are UNSIGNED. Set the signing config to enable."
    echo ""
    exit 0
fi

if ! command -v osslsigncode > /dev/null 2>&1; then
    echo "  [sign] ERROR: osslsigncode is required to sign the Windows agent."
    echo "  [sign] Install it with:  apt install osslsigncode   (or: brew install osslsigncode)"
    exit 1
fi

if [ ! -f "$CERT_FILE" ]; then
    echo "  [sign] ERROR: certificate file not found: $CERT_FILE"
    exit 1
fi

# Determine sign arguments depending on cert type (.pfx/.p12 vs PEM).
SIGN_ARGS=""
case "$CERT_FILE" in
    *.pfx|*.PFX|*.p12|*.P12)
        if [ -n "$CERT_PASS" ]; then
            SIGN_ARGS="-pkcs12 \"$CERT_FILE\" -pass \"$CERT_PASS\""
        else
            SIGN_ARGS="-pkcs12 \"$CERT_FILE\""
        fi
        ;;
    *)
        SIGN_ARGS="-certs \"$CERT_FILE\""
        if [ -n "$CERT_KEY" ]; then
            SIGN_ARGS="$SIGN_ARGS -key \"$CERT_KEY\""
        fi
        if [ -n "$CERT_PASS" ]; then
            SIGN_ARGS="$SIGN_ARGS -pass \"$CERT_PASS\""
        fi
        ;;
esac

echo ""
echo "  [sign] Signing Unishield 360 Windows agent..."
echo "  [sign] Cert       : $CERT_FILE"
echo "  [sign] CA_NAME    : $CA_NAME"
echo "  [sign] Timestamp  : $TIMESTAMP_URL"
echo ""

SIGNED_COUNT=0
SKIP_COUNT=0

sign_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return
    fi
    # Skip files that are already signed.
    if osslsigncode verify -in "$file" > /dev/null 2>&1; then
        echo "  [sign] already signed, skipping: $(basename "$file")"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return
    fi
    echo "  [sign] signing: $(basename "$file")"
    # shellcheck disable=SC2086
    if osslsigncode sign \
        $(eval echo $SIGN_ARGS) \
        -h sha256 \
        -t "$TIMESTAMP_URL" \
        -in "$file" \
        -out "$file.signed" > /dev/null 2>&1; then
        mv "$file.signed" "$file"
        SIGNED_COUNT=$((SIGNED_COUNT + 1))
    else
        echo "  [sign] WARNING: failed to sign $(basename "$file")"
        rm -f "$file.signed"
    fi
}

echo "  [sign] Searching for binaries in: $BUILD_DIR"
echo ""

# Sign all EXEs and DLLs in the build directory.
while IFS= read -r -d '' file; do
    sign_file "$file"
done < <(find "$BUILD_DIR" -maxdepth 1 \( -name '*.exe' -o -name '*.dll' \) -print0 2>/dev/null || true)

# Sign the NSIS installer if present.
sign_file "$BUILD_DIR/unishield-agent-"*.exe

echo ""
echo "  [sign] Done: $SIGNED_COUNT signed, $SKIP_COUNT already signed."
echo ""

# --- Align Wazuh trust verification CA name ---
if [ -n "$CA_NAME" ]; then
    echo "  [sign] Note: build with CA_NAME=\"$CA_NAME\" so Wazuh's"
    echo "  [sign]       IMAGE_TRUST_CHECKS verifies against the correct root."
    echo ""
fi

exit 0