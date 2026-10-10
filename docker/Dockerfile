# Airclone in a container: the Linux build, serving its Web UI.
#
# Built by release.yml from the release's own Linux bundle, one image per
# architecture on its native runner, then joined into one multi-arch tag. The
# build context holds that bundle at bundle/, extracted from
# airclone-linux-<arch>.tar.gz; nothing is compiled here.
#
# Ubuntu 24.04 because the bundle is built on ubuntu-latest (24.04) and needs
# its glibc. The runtime libraries are the ones the tarball says it needs
# (README, "On Linux"): GTK 3, libmpv, libsecret, ALSA. Xvfb because the Linux
# engine can only be started against a display server, even with no window
# (docs/guide/web-ui.md).
FROM ubuntu:24.04

ARG AIRCLONE_VERSION=dev
LABEL org.opencontainers.image.title="Airclone" \
      org.opencontainers.image.description="rclone in your browser: the Airclone Web UI" \
      org.opencontainers.image.source="https://github.com/GigaionLLC/Airclone" \
      org.opencontainers.image.url="https://github.com/GigaionLLC/Airclone/blob/main/docs/guide/docker.md" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.vendor="Gigaion LLC" \
      org.opencontainers.image.version="${AIRCLONE_VERSION}"

# OpenGL ES + EGL with Mesa's software renderer (libgles2, libegl1,
# libgl1-mesa-dri): the Linux engine refuses to start without libGLESv2.so.2
# even for --webui, which the first smoke-test run caught. There is no GPU in
# here and none is needed. The ubuntu user is replaced by "airclone", which the
# entrypoint gives PUID/PGID at start.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libgtk-3-0t64 libmpv2 libsecret-1-0 libasound2t64 \
      libgles2 libegl1 libgl1-mesa-dri \
      xvfb xauth tini gosu curl ca-certificates tzdata fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/* \
 && (userdel -r ubuntu 2>/dev/null || true) \
 && groupadd -g 1000 airclone \
 && useradd -u 1000 -g 1000 -M -d /data -s /usr/sbin/nologin airclone \
 && mkdir -p /config /data /var/cache/airclone

COPY bundle/ /opt/airclone/
COPY entrypoint.sh /usr/local/bin/airclone-entrypoint
RUN chmod 755 /usr/local/bin/airclone-entrypoint /opt/airclone/airclone

# Everything Airclone keeps (rclone.conf, the Web UI login and certificate,
# saved tasks) lands under /config through the XDG variables. HOME is /data so
# the app's "Home" location is the folder you mounted, and nothing is written
# into it: every path the app writes to is redirected above.
ENV HOME=/data \
    XDG_DATA_HOME=/config \
    XDG_CONFIG_HOME=/config/settings \
    XDG_CACHE_HOME=/var/cache/airclone \
    PUID=1000 \
    PGID=1000

VOLUME ["/config"]
EXPOSE 5799

# The login page answers without signing in. -k: the certificate is the
# self-signed one Airclone made, which is expected.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsk -o /dev/null https://127.0.0.1:5799/login || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/airclone-entrypoint"]
