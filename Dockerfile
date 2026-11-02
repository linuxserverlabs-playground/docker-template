# syntax=docker/dockerfile:1

# A playground base image: s6-overlay, the abc user (PUID/PGID), /config. Keep the tag the playground publishes.
FROM ghcr.io/linuxserver-playground/baseimage-alpine:3.24

# set version label
ARG BUILD_DATE
ARG VERSION
# TODO: <APP>_RELEASE, the name in image.yml build.version_arg. The pipeline passes the release tag it resolved.
ARG MYAPP_RELEASE
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
# TODO: your GitHub login
LABEL maintainer="your-github-login"

# environment settings
ENV HOME="/config"

# TODO: the upstream repository (twice) and this architecture's release asset. With no MYAPP_RELEASE (a plain
# local build) the latest release is used. Add any runtime packages the app needs to apk add.
RUN \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    ca-certificates && \
  echo "**** install myapp ****" && \
  if [ -z ${MYAPP_RELEASE+x} ]; then \
    MYAPP_RELEASE=$(curl -sX GET "https://api.github.com/repos/example-org/myapp/releases/latest" \
      | jq -r '.tag_name'); \
  fi && \
  mkdir -p \
    /app/myapp && \
  curl -o \
    /tmp/myapp.tar.gz -fL \
    "https://github.com/example-org/myapp/releases/download/${MYAPP_RELEASE}/myapp-${MYAPP_RELEASE#v}-linux-amd64.tar.gz" && \
  tar xf \
    /tmp/myapp.tar.gz -C \
    /app/myapp && \
  printf "Linuxserver.io version: ${VERSION}\nBuild-date: ${BUILD_DATE}" > /build_version && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/*

# add local files
COPY root/ /

# ports and volumes
# TODO: the app's web port, as in image.yml
EXPOSE 8080
VOLUME /config
