FROM debian:trixie-slim

ARG USER=user

RUN \
    apt-get update && apt-get install -y sudo which curl && \
    groupadd -g 1000 $USER && \
    useradd -g 1000 -u 1000 -m $USER && \
    usermod -a -G sudo $USER && \
    echo "$USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER $USER

RUN bash -c 'if [ -z "$(which curl)" ]; then echo "Curl missing. Aborting."; else bash <(curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/setup.sh -- --noconfirm --skip=docker --skip=alacritty 2>/dev/null); fi'

ENTRYPOINT ["tail", "-F", "/dev/null"]
