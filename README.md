# nginx mTLS Proxy

A lightweight nginx-based proxy that enables applications to connect to external services requiring mutual TLS (mTLS) authentication without modifying application code.

## Overview

This project provides a slim Docker image that acts as a transparent proxy, handling mTLS authentication on behalf of your applications. It's particularly useful in Kubernetes deployments where you need to connect to external services that require client certificates, but you don't want to modify your application code to handle certificate management.

## Key Features

- **Zero Code Changes**: Applications connect to the proxy using standard HTTP/HTTPS
- **mTLS Handling**: Proxy manages client certificate authentication with upstream services
- **Kubernetes Ready**: Designed as a sidecar container with mounted certificates
- **Lightweight**: Based on nginx:alpine for minimal resource footprint
- **Configurable**: Environment variables for easy configuration

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
| `MTLS_CERT_PATH` | Path to client certificate file | Yes | - |
| `MTLS_KEY_PATH` | Path to client private key file | Yes | - |
| `MTLS_CA_CERT_PATH` | Path to CA certificate file for verification | No | - |
| `MTLS_VERIFY_CERT` | Enable SSL certificate verification (on/off) | No | off |
| `PORT` | Port for the proxy to listen on | No | 8888 |

## CA Certificate Verification

The proxy supports optional CA certificate verification for enhanced security:

- **Without CA verification**: The proxy will accept any certificate from the target server
- **With CA verification**: The proxy will verify the target server's certificate against the provided CA certificate

To enable CA verification:
1. Mount the CA certificate file into the container
2. Set `MTLS_CA_CERT_PATH` to the path of the CA certificate
3. Set `MTLS_VERIFY_CERT=on` to enable verification

## Usage

### Docker Run (Basic)

```bash
docker run -d \
  -p 8888:8888 \
  -v /path/to/certs:/certs \
  -e PROXY_TARGET=https://api.example.com \
  -e MTLS_CERT_PATH=/certs/client.pem \
  -e MTLS_KEY_PATH=/certs/client-key.pem \
  techcoil/nginx-mtls-proxy
```

### Docker Run (With CA Verification)

```bash
docker run -d \
  -p 8888:8888 \
  -v /path/to/certs:/certs \
  -e PROXY_TARGET=https://api.example.com \
  -e MTLS_CERT_PATH=/certs/client.pem \
  -e MTLS_KEY_PATH=/certs/client-key.pem \
  -e MTLS_CA_CERT_PATH=/certs/ca.pem \
  -e MTLS_VERIFY_CERT=on \
  techcoil/nginx-mtls-proxy
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
        # Your application connects to localhost:8888 instead of the external service
        env:
        - name: EXTERNAL_API_URL
          value: "http://localhost:8888"
      
      - name: mtls-proxy
        image: techcoil/nginx-mtls-proxy
        ports:
        - containerPort: 8888
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
version: '3.8'
services:
  my-app:
    image: my-app:latest
    environment:
      - EXTERNAL_API_URL=http://mtls-proxy:8888
    depends_on:
      - mtls-proxy

  mtls-proxy:
    build: .
    environment:
      - PROXY_TARGET=https://api.example.com
      - MTLS_CERT_PATH=/certs/client.pem
      - MTLS_KEY_PATH=/certs/client-key.pem
    volumes:
      - ./certs:/certs:ro
    ports:
      - "8888:8888"
```

## Building

Build the Docker image:

```bash
docker build -t nginx-mtls-proxy .
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
- Use `MTLS_VERIFY_CERT=on` to enable strict verification
- If verification fails, the proxy will reject the connection

### Security Best Practices

- Store certificates as Kubernetes secrets
- Use proper RBAC to limit access to certificate secrets
- Rotate certificates regularly
- Monitor certificate expiration dates

## Troubleshooting

### Common Issues

1. **Certificate not found**: Ensure certificate paths are correct and files are mounted
2. **Permission denied**: Check file permissions on mounted certificate files
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
3. Make your changes
4. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues and questions, please open an issue on the GitHub repository.