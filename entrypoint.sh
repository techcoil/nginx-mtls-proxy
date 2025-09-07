#!/bin/sh

# Set default values for optional configuration
MTLS_VERIFY_CERT=${MTLS_VERIFY_CERT:-"off"}

# Generate conditional configuration strings
MTLS_CA_CONFIG=""
MTLS_VERIFY_CONFIG=""
MTLS_CERTIFICATES=""

if [ -z "$PROXY_TARGET" ]; then
	echo "[ERROR] PROXY_TARGET is a required env variable" >&2
	exit 1
fi

# Only add CA certificate configuration if MTLS_CA_CERT_PATH is set and file exists
if [ -n "$MTLS_CA_CERT_PATH" ] && [ -f "$MTLS_CA_CERT_PATH" ]; then
    echo "[INFO] Using CA certificate: $MTLS_CA_CERT_PATH"
    MTLS_CA_CONFIG="proxy_ssl_trusted_certificate \"$MTLS_CA_CERT_PATH\";"
    
    # Only add verification config if CA cert is present
    if [ "$MTLS_VERIFY_CERT" != "off" ]; then
        echo "[INFO] Enabling certificate verification: $MTLS_VERIFY_CERT"
        MTLS_VERIFY_CONFIG="proxy_ssl_verify $MTLS_VERIFY_CERT;"
    fi
else
    echo "[WARNING] No CA certificate configured or file not found. SSL verification disabled."
    MTLS_CA_CONFIG="# No CA certificate configured"
    MTLS_VERIFY_CONFIG="# SSL verification disabled"
fi

if [ -n "$MTLS_CERT_PATH" ] && [ -f "$MTLS_CERT_PATH" ] && [ -n "$MTLS_KEY_PATH" ] && [ -f "$MTLS_KEY_PATH" ]; then
	MTLS_CERTIFICATES="\
		proxy_ssl_certificate "${MTLS_CERT_PATH}";\
		proxy_ssl_certificate_key "${MTLS_KEY_PATH}";"
else 
	echo "[WARNING] Proxy running with NO mtls - to configure mtls, you must provide both MTLS_CERT_PATH and MTLS_KEY_PATH" >&2
fi

# Export the configuration variables for envsubst
export MTLS_CA_CONFIG
export MTLS_VERIFY_CONFIG
export MTLS_CERTIFICATES

# Start nginx with the original Docker entrypoint
exec /docker-entrypoint.sh "$@"
