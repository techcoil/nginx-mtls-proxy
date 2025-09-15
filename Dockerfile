FROM nginxinc/nginx-unprivileged:latest

ARG PORT=8080

USER 0
RUN apt update

RUN mkdir -p /etc/nginx/templates
COPY proxy.conf /etc/nginx/templates/default.conf.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make entrypoint script executable
RUN chmod +x /usr/local/bin/entrypoint.sh

USER 1001
# Environment variables for proxy configuration
#ENV PROXY_TARGET=
#ENV PROXY_HOST_HEADER=
#ENV MTLS_KEY_PATH=
#ENV MTLS_CERT_PATH=
#ENV MTLS_CA_CERT_PATH=
#ENV MTLS_VERIFY_CERT=off
ENV PORT=$PORT

EXPOSE $PORT

# Use custom entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
