# syntax=docker/dockerfile:1
# Build context: the repository root (server/ depends on ../shared).
ARG DART_VERSION=stable
FROM dart:${DART_VERSION} AS build
WORKDIR /src
COPY shared/pubspec.yaml shared/
COPY server/pubspec.yaml server/pubspec.lock server/
RUN cd server && dart pub get
COPY shared shared
COPY server server
# `dart build cli`, not `dart compile exe`: sqlite3 ships its native library through a build hook.
RUN cd server && dart pub get --offline && dart build cli --target bin/server.dart -o /out

FROM debian:bookworm-slim
ARG VERSION=dev
LABEL org.opencontainers.image.title="unfeudal-server" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/unfeudal/unfeudal" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home-dir /data --shell /usr/sbin/nologin unfeudal \
 && mkdir -p /data && chown 10001 /data
COPY --from=build /out/bundle /opt/unfeudal
RUN ln -s /opt/unfeudal/bin/server /usr/local/bin/unfeudal-server
COPY server/LICENSE /usr/share/doc/unfeudal/LICENSE
USER 10001
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s CMD ["unfeudal-server", "healthcheck"]
STOPSIGNAL SIGTERM
ENTRYPOINT ["unfeudal-server"]
