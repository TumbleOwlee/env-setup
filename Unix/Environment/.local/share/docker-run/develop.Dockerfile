FROM debian:bookworm-slim

ARG LLVM=YES
ARG DEV_ENV=NO

ENV USER_ID=1000
ENV GROUP_ID=1000
ENV USER_NAME=dev
ENV GROUP_NAME=dev

# Setup dev user
RUN groupadd -g ${GROUP_ID} ${GROUP_NAME} && \
    useradd --shell /bin/bash -m -p "" --uid ${USER_ID} -g ${GROUP_NAME} ${USER_NAME} && \
    apt-get update && \
    apt-get install -y sudo && \
    usermod -aG sudo ${USER_NAME} && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers

USER ${USER_NAME}

ENV PATH="$PATH:/home/${USER_NAME}/.local/bin:/home/${USER_NAME}/.cargo/bin"

RUN sudo apt-get update && \
    sudo apt-get install -y ninja-build build-essential cmake gdb iputils-ping curl vim which ccache && \
    bash -c 'bash <(curl https://raw.githubusercontent.com/TumbleOwlee/env-setup/main/Unix/setup.sh 2>/dev/null) --noconfirm --skip=alacritty --skip=docker' && \
    git config --global --add safe.directory /git && \
    sudo apt-get clean
