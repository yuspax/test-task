FROM nginx:1.30.5-alpine

ENV APP_UPSTREAM=app:8000

COPY nginx.conf /etc/nginx/nginx.conf.template
COPY --chmod=755 entrypoint.sh /usr/local/bin/start-nginx

USER nginx
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null -T 2 http://127.0.0.1:8080/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/start-nginx"]
CMD []
