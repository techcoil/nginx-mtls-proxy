#!/bin/bash

# Generate throwaway certificates for test-ca.sh.
# Nothing generated here is trusted anywhere - never add these CAs to a trust store.
#
# Usage: gen-certs.sh [output-dir]   (default: test-certs/generated)
#
# Output:
#   ca.crt / ca.key                      - test CA
#   server.pem / server-key.pem          - backend server cert signed by the test CA
#   client.pem / client-key.pem          - mTLS client cert signed by the test CA
#   untrusted-ca.crt / untrusted-ca.key  - unrelated CA, for negative tests
#   untrusted-server.pem / untrusted-server-key.pem - backend server cert signed by the untrusted CA
#   untrusted-client.pem / untrusted-client-key.pem - mTLS client cert signed by the untrusted CA
set -e

OUT_DIR="${1:-$(dirname "$0")/generated}"
DAYS=7300 # ~20 years
SERVER_SAN="DNS:localhost,DNS:host.docker.internal,IP:127.0.0.1,IP:::1"

if ! command -v openssl &> /dev/null; then
    echo "openssl is not installed. Please install openssl to generate test certificates."
    exit 1
fi

mkdir -p "$OUT_DIR"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Extension files are passed via -extfile so this works with both OpenSSL and LibreSSL
cat > "$WORK_DIR/ca.ext" <<EOF
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF

cat > "$WORK_DIR/server.ext" <<EOF
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = ${SERVER_SAN}
EOF

cat > "$WORK_DIR/client.ext" <<EOF
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

# new_ca <name> <common-name>
new_ca() {
  openssl req -new -nodes -newkey rsa:2048 \
    -keyout "$OUT_DIR/$1.key" -out "$WORK_DIR/$1.csr" -subj "/O=nginx-mtls-proxy test/CN=$2" 2> /dev/null
  openssl x509 -req -days $DAYS -sha256 \
    -in "$WORK_DIR/$1.csr" -signkey "$OUT_DIR/$1.key" \
    -extfile "$WORK_DIR/ca.ext" -out "$OUT_DIR/$1.crt" 2> /dev/null
}

# new_cert <name> <common-name> <ext-file> <ca-name>
new_cert() {
  openssl req -new -nodes -newkey rsa:2048 \
    -keyout "$OUT_DIR/$1-key.pem" -out "$WORK_DIR/$1.csr" -subj "/O=nginx-mtls-proxy test/CN=$2" 2> /dev/null
  openssl x509 -req -days $DAYS -sha256 \
    -in "$WORK_DIR/$1.csr" -CA "$OUT_DIR/$4.crt" -CAkey "$OUT_DIR/$4.key" -CAcreateserial \
    -extfile "$WORK_DIR/$3" -out "$OUT_DIR/$1.pem" 2> /dev/null
}

new_ca ca "nginx-mtls-proxy test CA"
new_cert server "localhost" server.ext ca
new_cert client "test-client" client.ext ca

new_ca untrusted-ca "nginx-mtls-proxy untrusted test CA"
new_cert untrusted-server "localhost" server.ext untrusted-ca
new_cert untrusted-client "untrusted-test-client" client.ext untrusted-ca

rm -f "$OUT_DIR"/*.srl

# nginx in the container runs as a non-root user and must be able to read the mounted keys
chmod 644 "$OUT_DIR"/*

echo "Test certificates generated in $OUT_DIR"
