# Minimal development image. Requires BuildKit (the default since Docker 23).
#   docker build --build-arg DEBIAN_VERSION=13 -t dev-env .
ARG DEBIAN_VERSION=stable
FROM debian:${DEBIAN_VERSION}-slim

ARG DEV_USER=dev
# Additional flags for setup.sh, e.g. --include=docker,mise
ARG SETUP_FLAGS=

ENV LANG=C.UTF-8

# A single RUN and a bind mount instead of COPY: what is deleted at the end of a
# layer doesn't count, what was added by an earlier layer stays in the image.
RUN --mount=type=bind,source=Unix,target=/tmp/env-setup/Unix \
    set -e; \
    apt-get update; \
    apt-get install -y --no-install-recommends sudo; \
    useradd -m "$DEV_USER"; \
    echo "$DEV_USER ALL=(ALL) NOPASSWD:ALL" >"/etc/sudoers.d/$DEV_USER"; \
    chmod 440 "/etc/sudoers.d/$DEV_USER"; \
    runuser -u "$DEV_USER" -- env HOME="/home/$DEV_USER" \
        bash /tmp/env-setup/Unix/setup.sh --noconfirm --minimal $SETUP_FLAGS

USER ${DEV_USER}
WORKDIR /home/${DEV_USER}
CMD ["fish"]
