#!/bin/sh

# Set default values for optional configuration
if [ -z "$MTLS_VERIFY_CERT" ]; then
	if [ -z "$MTLS_CA_CERT_PATH" ]; then
		MTLS_VERIFY_CERT="off"
	else
		MTLS_VERIFY_CERT="on"
	fi
fi

# Generate conditional configuration strings
MTLS_CA_CONFIG=""
MTLS_VERIFY_CONFIG=""
MTLS_CERTIFICATES=""
HOST_HEADER_CONFIG=""

if [ -z "$PROXY_TARGET" ]; then
	echo "[ERROR] PROXY_TARGET is a required env variable" >&2
	exit 1
fi

if [ -z "$PROXY_HOST_HEADER" ]; then
	PROXY_HOST_HEADER='$host'
else 
	echo "[INFO] Configuring Host override for ${PROXY_HOST_HEADER}"
fi

HOST_HEADER_CONFIG="proxy_set_header Host ${PROXY_HOST_HEADER};"

# Only add CA certificate configuration if MTLS_CA_CERT_PATH is set and file exists
if [ -n "$MTLS_CA_CERT_PATH" ] && [ -f "$MTLS_CA_CERT_PATH" ]; then
    echo "[INFO] Using CA certificate: $MTLS_CA_CERT_PATH"
    MTLS_CA_CONFIG="proxy_ssl_trusted_certificate \"$MTLS_CA_CERT_PATH\";"
    
    # Only add verification config if CA cert is present
    if [ "$MTLS_VERIFY_CERT" != "off" ]; then
        echo "[INFO] Enabling certificate verification: $MTLS_VERIFY_CERT"
        MTLS_VERIFY_CONFIG="proxy_ssl_verify $MTLS_VERIFY_CERT;"
        if [ -n "$MTLS_VERIFY_DEPTH" ]; then
            MTLS_VERIFY_CONFIG="$MTLS_VERIFY_CONFIG\nproxy_ssl_verify_depth $MTLS_VERIFY_DEPTH;"
        fi
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
export HOST_HEADER_CONFIG

# Start nginx with the original Docker entrypoint
exec /docker-entrypoint.sh "$@"
