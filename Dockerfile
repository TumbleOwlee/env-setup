# Minimal development image. Requires BuildKit (the default since Docker 23).
#   docker build --build-arg DEBIAN_VERSION=13 -t dev-env .
ARG DEBIAN_VERSION=stable
FROM debian:${DEBIAN_VERSION}-slim

ARG DEV_USER=dev
# uid and gid of the user. Use the ones of your host user to access mounted files.
ARG DEV_UID=1000
ARG DEV_GID=1000
# Additional flags for setup.sh, e.g. --include=docker,mise
ARG SETUP_FLAGS=

ENV LANG=C.UTF-8

# A single RUN and a bind mount instead of COPY: what is deleted at the end of a
# layer doesn't count, what was added by an earlier layer stays in the image.
RUN --mount=type=bind,source=Unix,target=/tmp/dotstrap/Unix \
    set -e; \
    apt-get update; \
    apt-get install -y --no-install-recommends sudo; \
    if ! getent group "$DEV_GID" >/dev/null; then groupadd -g "$DEV_GID" "$DEV_USER"; fi; \
    useradd -m -u "$DEV_UID" -g "$DEV_GID" "$DEV_USER"; \
    echo "$DEV_USER ALL=(ALL) NOPASSWD:ALL" >"/etc/sudoers.d/$DEV_USER"; \
    chmod 440 "/etc/sudoers.d/$DEV_USER"; \
    runuser -u "$DEV_USER" -- env HOME="/home/$DEV_USER" \
        bash /tmp/dotstrap/Unix/setup.sh --noconfirm --minimal $SETUP_FLAGS

# The shell startup files add these too, but 'docker run <image> <cmd>' reads none
ENV PATH=${PATH}:/home/${DEV_USER}/.local/bin:/home/${DEV_USER}/.cargo/bin

USER ${DEV_USER}
WORKDIR /home/${DEV_USER}
CMD ["fish"]
