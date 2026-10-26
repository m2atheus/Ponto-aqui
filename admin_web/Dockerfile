FROM nginx:alpine

ENV NGINX_ENTRYPOINT_WORKER_PROCESSES_AUTOTUNE=1

COPY nginx.conf /etc/nginx/conf.d/default.conf
# flutter build web runs on the developer machine, never in this image.
COPY build/web/ /usr/share/nginx/html/

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
