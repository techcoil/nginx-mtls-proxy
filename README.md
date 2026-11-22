# nginx mTLS Proxy

[![Docker Repository on Quay](https://quay.io/repository/techcoil/nginx-mtls-proxy/status "Docker Repository on Quay")](https://quay.io/repository/techcoil/nginx-mtls-proxy)

A lightweight nginx-based reverse proxy that enables applications to connect to external services requiring client certificate (mTLS) authentication without modifying application code.

## Overview

This project provides a slim Docker image that acts as a transparent proxy, handling mTLS authentication on behalf of your applications. It's particularly useful in Kubernetes deployments where you need to connect to external services that require client certificates, but you don't want to modify your application code to handle certificate management.

## Key Features

- **Zero Code Changes**: Applications connect to the proxy using standard HTTP/HTTPS
- **mTLS Handling**: Proxy manages client certificate authentication with upstream services
- **Kubernetes Ready**: Designed as a sidecar container with mounted certificates
- **Lightweight & Non-root**: Based on [`nginx/nginx-unprivileged`](https://hub.docker.com/r/nginx/nginx-unprivileged) (nginx stable, Alpine)
- **Configurable**: Environment variables for easy configuration
- **Kept Up to Date**: New nginx stable releases are picked up, tested and published automatically

## Use Cases

- **Kubernetes Sidecar**: Deploy alongside your application pods to handle mTLS requirements
- **Legacy Application Integration**: Add mTLS support to applications without code changes
- **Certificate Management**: Centralize client certificate handling in containerized environments
- **Microservices**: Enable mTLS communication between services transparently

## Configuration

The proxy is configured using environment variables:

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `PROXY_TARGET` | Target URL to proxy requests to | Yes | - |
| `MTLS_CERT_PATH` | Path to client certificate file | For mTLS | - |
| `MTLS_KEY_PATH` | Path to client private key file | For mTLS | - |
| `MTLS_CA_CERT_PATH` | Path to CA certificate file for verifying the target server | No | - |
| `MTLS_VERIFY_CERT` | Verify the target server's certificate (`on`/`off`) | No | `on` when `MTLS_CA_CERT_PATH` is set, otherwise `off` |
| `MTLS_VERIFY_DEPTH` | Maximum certificate chain depth when verifying the target server | No | nginx default (1) |
| `PROXY_HOST_HEADER` | `Host` header sent to the target | No | Host of `PROXY_TARGET` |
| `PORT` | Port for the proxy to listen on | No | 8080 |

If `MTLS_CERT_PATH` and `MTLS_KEY_PATH` are not both set (and the files exist), the proxy runs as a plain reverse proxy without a client certificate and logs a warning.

## CA Certificate Verification

The proxy supports optional CA certificate verification for enhanced security:

- **Without CA verification**: The proxy will accept any certificate from the target server
- **With CA verification**: The proxy will verify the target server's certificate against the provided CA certificate

To enable CA verification:
1. Mount the CA certificate file into the container
2. Set `MTLS_CA_CERT_PATH` to the path of the CA certificate

Verification is enabled automatically when a CA certificate is configured. Set `MTLS_VERIFY_CERT=off` to load the CA without enforcing verification.

## Image Tags

Images are published to [`quay.io/techcoil/nginx-mtls-proxy`](https://quay.io/repository/techcoil/nginx-mtls-proxy) for `linux/amd64` and `linux/arm64`.

| Tag | Example | Meaning |
|-----|---------|---------|
| `v<version>` | `v0.0.6` | Proxy release, rebuilt automatically on the newest nginx stable (recommended) |
| `v<version>-nginx-<nginx-version>` | `v0.0.6-nginx-1.30.7` | Proxy release on a specific nginx version |
| `nginx-<nginx-version>` | `nginx-1.30.7` | Newest proxy release on a specific nginx version |

The proxy version only changes when the proxy itself changes. New nginx releases and base image security fixes are published as rebuilds of the current version: `v<version>` moves to the new build, and a new `v<version>-nginx-<nginx-version>` tag is added. Each release's GitHub release notes list all of its builds.

Every release is signed with [cosign](https://github.com/sigstore/cosign) (keyless) and ships with SBOM and provenance attestations. The GitHub release notes include the exact `cosign verify` command.

## Usage

### Docker Run (Basic)

```bash
docker run -d \
  -p 8080:8080 \
  -v /path/to/certs:/certs \
  -e PROXY_TARGET=https://api.example.com \
  -e MTLS_CERT_PATH=/certs/client.pem \
  -e MTLS_KEY_PATH=/certs/client-key.pem \
  quay.io/techcoil/nginx-mtls-proxy:v0.0.6
```

### Docker Run (With CA Verification)

```bash
docker run -d \
  -p 8080:8080 \
  -v /path/to/certs:/certs \
  -e PROXY_TARGET=https://api.example.com \
  -e MTLS_CERT_PATH=/certs/client.pem \
  -e MTLS_KEY_PATH=/certs/client-key.pem \
  -e MTLS_CA_CERT_PATH=/certs/ca.pem \
  quay.io/techcoil/nginx-mtls-proxy:v0.0.6
```

### Kubernetes Sidecar

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        # Your application connects to localhost:8080 instead of the external service
        env:
        - name: EXTERNAL_API_URL
          value: "http://localhost:8080"
      
      - name: mtls-proxy
        image: quay.io/techcoil/nginx-mtls-proxy:v0.0.6
        ports:
        - containerPort: 8080
        env:
        - name: PROXY_TARGET
          value: "https://external-api.example.com"
        - name: MTLS_CERT_PATH
          value: "/certs/client.pem"
        - name: MTLS_KEY_PATH
          value: "/certs/client-key.pem"
        volumeMounts:
        - name: mtls-certs
          mountPath: /certs
          readOnly: true
      
      volumes:
      - name: mtls-certs
        secret:
          secretName: mtls-certificates
```

### Docker Compose

```yaml
services:
  my-app:
    image: my-app:latest
    environment:
      - EXTERNAL_API_URL=http://mtls-proxy:8080
    depends_on:
      - mtls-proxy

  mtls-proxy:
    image: quay.io/techcoil/nginx-mtls-proxy:v0.0.6
    environment:
      - PROXY_TARGET=https://api.example.com
      - MTLS_CERT_PATH=/certs/client.pem
      - MTLS_KEY_PATH=/certs/client-key.pem
    volumes:
      - ./certs:/certs:ro
    ports:
      - "8080:8080"
```

## Certificate Management

### Certificate Requirements

- Client certificates must be in PEM format
- Private keys must be in PEM format and unencrypted
- CA certificates (if used) must be in PEM format
- Certificates should be properly mounted into the container

### CA Certificate Verification

When `MTLS_CA_CERT_PATH` is provided:
- The proxy will verify the target server's certificate against the CA
- Use `MTLS_VERIFY_DEPTH` if the target's certificate is issued by an intermediate CA
- If verification fails, the proxy will reject the connection (HTTP 502)

### Security Best Practices

- Store certificates as Kubernetes secrets
- Use proper RBAC to limit access to certificate secrets
- Rotate certificates regularly
- Monitor certificate expiration dates

## Troubleshooting

### Common Issues

1. **Certificate not found**: Ensure certificate paths are correct and files are mounted
2. **Permission denied**: Check file permissions on mounted certificate files (the container runs as a non-root user)
3. **SSL handshake failed**: Verify certificate validity and CA trust chain
4. **Connection refused**: Ensure the target service is accessible and accepts the client certificate

### Debug Mode

To enable nginx debug logging, modify the Dockerfile to include:

```dockerfile
RUN echo "error_log /var/log/nginx/error.log debug;" >> /etc/nginx/nginx.conf
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes and run the tests (`./test-ca.sh`)
4. Submit a pull request

Building, testing and the release process are described in the [Maintainers Guide](MAINTAINERS.md).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues and questions, please open an issue on the GitHub repository.
