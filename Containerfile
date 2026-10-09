# Les scripts de build sont montés pendant le build, sans être copiés dans l'image.
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Sans digest : le build de chaque nuit reprend la dernière Aurora stable.
FROM ghcr.io/ublue-os/aurora:stable

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN bootc container lint
