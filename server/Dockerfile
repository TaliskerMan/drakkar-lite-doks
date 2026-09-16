# Drakkar Lite API image.
# Build from the demo/ directory (the server depends on ../core):
#   docker buildx build --platform linux/amd64 -f server/Dockerfile -t <image> .

FROM dart:stable AS build
WORKDIR /src
COPY core/ core/
COPY server/pubspec.* server/
WORKDIR /src/server
RUN dart pub get
COPY server/ .
RUN dart pub get --offline \
 && mkdir -p /out \
 && dart compile exe bin/server.dart -o /out/server

# Minimal runtime: the AOT binary plus the few system libraries the official
# Dart image collects in /runtime. No shell, no package manager.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/server"]
CMD ["serve"]
