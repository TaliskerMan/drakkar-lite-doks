# Drakkar Lite web image. Build the Flutter app first:
#   flutter build web --release
# then, from the web/ directory:
#   docker buildx build --platform linux/amd64 -t <image> .
# The static files are CPU-independent; --platform only selects the nginx base.

FROM nginxinc/nginx-unprivileged:stable-alpine
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY build/web/ /usr/share/nginx/html/
ENV API_UPSTREAM=http://drakkar-api:8080
EXPOSE 8080
