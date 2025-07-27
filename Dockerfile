FROM nginx:alpine

RUN mkdir -p /etc/nginx/templates
COPY proxy.conf /etc/nginx/templates/default.conf.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make entrypoint script executable
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create directory for certificates
RUN mkdir -p /etc/ssl/certs

# Environment variables for proxy configuration
#ENV PROXY_TARGET=
#ENV MTLS_KEY_PATH=
#ENV MTLS_CERT_PATH=
#ENV MTLS_CA_CERT_PATH=
#ENV MTLS_VERIFY_CERT=off
ENV PORT=8888

EXPOSE 8888

# Use custom entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
