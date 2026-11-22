# Pinned by tag + digest; updated by Renovate (see renovate.json)
FROM nginx/nginx-unprivileged:1.30.7-alpine@sha256:0c53a1f2890c3526bfd201440f0fd3970e5b78f80630f58284aad0d34b5ec7bd

ARG PORT=8080

LABEL org.opencontainers.image.title="nginx-mtls-proxy" \
      org.opencontainers.image.description="nginx-based proxy that handles mTLS client authentication to upstream services" \
      org.opencontainers.image.source="https://github.com/techcoil/nginx-mtls-proxy" \
      org.opencontainers.image.licenses="MIT"

COPY proxy.conf /etc/nginx/templates/default.conf.template
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER 1001
# Environment variables for proxy configuration
#ENV PROXY_TARGET=
#ENV PROXY_HOST_HEADER=
#ENV MTLS_KEY_PATH=
#ENV MTLS_CERT_PATH=
#ENV MTLS_CA_CERT_PATH=
#ENV MTLS_VERIFY_CERT=off
#ENV MTLS_VERIFY_DEPTH=
ENV PORT=$PORT

EXPOSE $PORT

# Use custom entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
