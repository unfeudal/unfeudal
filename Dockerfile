# syntax=docker/dockerfile:1
# Build context: the repository root (server/ depends on ../shared).
FROM dart:3.13.6@sha256:bf07cd831c34d7cef047bcd50803fa38e3af59664a276440893ca9db77014ca0 AS build
WORKDIR /src/server
COPY shared/pubspec.yaml /src/shared/
COPY server/pubspec.yaml server/pubspec.lock ./
RUN dart pub get
COPY shared /src/shared
COPY server ./
# `dart build cli`, not `dart compile exe`: sqlite3 ships its native library through a build hook.
RUN dart pub get --offline && dart build cli --target bin/server.dart -o /out

# Same Debian release as the dart image, so the binary finds the glibc it was linked against.
FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
ARG VERSION=dev
LABEL org.opencontainers.image.title="unfeudal-server" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/unfeudal/unfeudal" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"
# ca-certificates follows the base image's security updates; a pinned version leaves the mirrors.
# hadolint ignore=DL3008
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
ENTRYPOINT ["unfeudal-server"]
