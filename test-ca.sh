#!/bin/bash

# Test script for nginx-mtls-proxy with CA certificate support
#
# Usage: test-ca.sh [-v]
#   -v  verbose: print the client certificate details received by the test servers
set -e

VERBOSE=0
while getopts "v" opt; do
  case $opt in
    v) VERBOSE=1 ;;
    *) echo "Usage: $0 [-v]"; exit 1 ;;
  esac
done

SERVER_PORT=5555
UNTRUSTED_SERVER_PORT=5556
BASIC_PORT=8888
CA_PORT=8889
UNTRUSTED_CA_PORT=8890
VERIFY_DEPTH_PORT=8891
CONTAINER_PORT=8080 # default PORT in the Dockerfile
CERT_DIR="test-certs/generated"
TEST_LABEL="nginx-mtls-proxy-test"
SERVER_PIDS=""
FAILED=0

# Verify that machine has Node.js, Docker and openssl installed
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Please install Node.js to run this test."
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install Docker to run this test."
    exit 1
fi

if ! command -v openssl &> /dev/null; then
    echo "openssl is not installed. Please install openssl to run this test."
    exit 1
fi

# Remove all test containers, including leftovers from previous runs
remove_test_containers() {
  local containers
  containers=$(docker ps -aq --filter "label=${TEST_LABEL}")
  if [ -n "$containers" ]; then
    docker rm -f $containers > /dev/null || true
  fi
}

cleanup() {
  echo "Cleaning up..."
  for pid in $SERVER_PIDS; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  remove_test_containers
}
trap cleanup EXIT
trap 'exit 130' INT TERM

port_in_use() {
  nc -z localhost "$1" > /dev/null 2>&1
}

# start_server <port> <server-cert-name>
start_server() {
  local pid timeout=10
  PORT=$1 CERT_DIR="$(pwd)/${CERT_DIR}" SERVER_CERT=$2 VERBOSE=$VERBOSE node test-certs/test-server.js &
  pid=$!
  SERVER_PIDS="$SERVER_PIDS $pid"

  # Wait for server to be ready. timeout after 10 seconds
  while ! port_in_use "$1"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "Server on port $1 exited unexpectedly"
      exit 1
    fi
    sleep 1
    timeout=$((timeout - 1))
    if [ $timeout -eq 0 ]; then
      echo "Server on port $1 did not start in time"
      exit 1
    fi
  done
}

# run_proxy <name> <host-port> <backend-port> [extra docker args...]
run_proxy() {
  local name=$1 port=$2 backend_port=$3
  shift 3
  docker run -d \
    --rm \
    --label "${TEST_LABEL}" \
    --name "nginx-mtls-proxy-test-${name}" \
    -p "${port}:${CONTAINER_PORT}" \
    --add-host=host.docker.internal:host-gateway \
    -v "$(pwd)/${CERT_DIR}:/certs" \
    -e PROXY_TARGET="https://host.docker.internal:${backend_port}" \
    -e MTLS_CERT_PATH="/certs/client.pem" \
    -e MTLS_KEY_PATH="/certs/client-key.pem" \
    "$@" \
    nginx-mtls-proxy > /dev/null
}

http_status() {
  curl -s -o /dev/null -w '%{http_code}' "http://localhost:$1" || true
}

# Wait until the proxy answers HTTP at all (any status code)
wait_for_proxy() {
  local timeout=10
  while [ "$(http_status "$1")" = "000" ]; do
    sleep 1
    timeout=$((timeout - 1))
    if [ $timeout -eq 0 ]; then
      echo "Proxy on port $1 did not start in time"
      return 1
    fi
  done
}

# expect_status <description> <port> <expected-status>
expect_status() {
  local status
  wait_for_proxy "$2" || true
  status=$(http_status "$2")
  if [ "$status" = "$3" ]; then
    echo "✅ $1 passed (HTTP $status)"
  else
    echo "❌ $1 failed (expected HTTP $3, got $status)"
    FAILED=1
  fi
}

remove_test_containers

for port in $SERVER_PORT $UNTRUSTED_SERVER_PORT $BASIC_PORT $CA_PORT $UNTRUSTED_CA_PORT $VERIFY_DEPTH_PORT; do
  if port_in_use "$port"; then
    echo "Port $port is already in use. Free it before running this test:"
    lsof -nP -iTCP:"$port" -sTCP:LISTEN || true
    exit 1
  fi
done

echo "Generating test certificates..."
rm -rf "${CERT_DIR}"
test-certs/gen-certs.sh "${CERT_DIR}"

echo "Building nginx-mtls-proxy image..."
docker build -t nginx-mtls-proxy .

echo "Starting test mTLS servers..."
start_server $SERVER_PORT server
start_server $UNTRUSTED_SERVER_PORT untrusted-server

echo "Starting proxies..."
run_proxy basic $BASIC_PORT $SERVER_PORT
run_proxy ca $CA_PORT $SERVER_PORT \
  -e MTLS_CA_CERT_PATH="/certs/ca.crt"
run_proxy untrusted-ca $UNTRUSTED_CA_PORT $UNTRUSTED_SERVER_PORT \
  -e MTLS_CA_CERT_PATH="/certs/ca.crt"
run_proxy verify-depth $VERIFY_DEPTH_PORT $SERVER_PORT \
  -e MTLS_CA_CERT_PATH="/certs/ca.crt" \
  -e MTLS_VERIFY_DEPTH=2

echo "Running tests..."
expect_status "Basic proxy (no CA verification)" $BASIC_PORT 200
expect_status "CA-verified proxy" $CA_PORT 200
expect_status "CA-verified proxy rejects backend cert from untrusted CA" $UNTRUSTED_CA_PORT 502
expect_status "CA-verified proxy with MTLS_VERIFY_DEPTH" $VERIFY_DEPTH_PORT 200

if [ $FAILED -ne 0 ]; then
  echo "Test failed!"
  exit 1
fi

echo "Test completed!"
