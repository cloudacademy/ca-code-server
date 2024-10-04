# syntax=docker/dockerfile:experimental
ARG BASE=ubuntu:24.04

# build is based on https://coder.com/docs/code-server/latest/CONTRIBUTING
FROM node:20.17-bookworm as build

ARG CODE_SERVER_VERSION=4.93.1
ARG VS_CODE_VERSION=1.93.1

RUN echo 'deb [trusted=yes] https://repo.goreleaser.com/apt/ /' | tee /etc/apt/sources.list.d/goreleaser.list
RUN apt-get update --allow-insecure-repositories
RUN apt-get install --allow-unauthenticated -y git-lfs yarn nfpm jq gnupg quilt rsync unzip bats \
                       build-essential g++ libx11-dev libxkbfile-dev libsecret-1-dev libkrb5-dev python-is-python3

WORKDIR /code-server
RUN echo "CODE_SERVER_VERSION = ${CODE_SERVER_VERSION}"
RUN git clone --branch "v${CODE_SERVER_VERSION}" https://github.com/coder/code-server.git . && \
    git submodule update --init
RUN sed -i 's/code-server"/ca-code-labs"/g' ci/build/build-vscode.sh
RUN jq ".version = \"${CODE_SERVER_VERSION}-calabs\"" package.json > /tmp/package.json && mv /tmp/package.json package.json && \
    jq ".codeServerVersion = \"${CODE_SERVER_VERSION}-calabs\"" lib/vscode/product.json > /tmp/product.json && mv /tmp/product.json lib/vscode/product.json && \
    chmod 644 lib/vscode/product.json
RUN quilt push -a
# remove insecure notification check without impacting other patches (look at https://github.com/coder/code-server/blob/main/patches/insecure-notification.diff for what to remove)
RUN sed -i '/if (!window.isSecureContext)/,+24d' lib/vscode/src/vs/workbench/browser/client.ts
RUN yarn install --frozen-lockfile
RUN yarn add ternary-stream # address 1.83.1 build issue https://github.com/cloudacademy/ca-code-server/actions/runs/6778516221/job/18424106568
RUN yarn build
RUN VERSION=${VS_CODE_VERSION} yarn build:vscode
RUN yarn release
RUN yarn release:standalone
RUN VERSION=${VS_CODE_VERSION} yarn package


# release is based on https://github.com/coder/code-server/blob/70aa1b77226ea40e5d661103de7b354f742a76df/ci/release-image/Dockerfile
FROM scratch AS packages
COPY --from=build /code-server/release-packages/code-server*.deb /tmp/

FROM $BASE as release

RUN apt-get update --allow-insecure-repositories \
  && apt-get install -y \
    curl \
    dumb-init \
    gnupg \
    zsh \
    htop \
    locales \
    man \
    nano \
    git \
    git-lfs \
    procps \
    openssh-client \
    sudo \
    vim.tiny \
    lsb-release \
  && git lfs install \
  && rm -rf /var/lib/apt/lists/* \
  && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 40976EAF437D05B5

# https://wiki.debian.org/Locale#Manually
RUN sed -i "s/# en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen \
  && locale-gen
ENV LANG=en_US.UTF-8

RUN adduser --gecos '' --disabled-password coder \
  && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd

RUN ARCH="$(dpkg --print-architecture)" \
  && curl -fsSL "https://github.com/boxboat/fixuid/releases/download/v0.5/fixuid-0.5-linux-$ARCH.tar.gz" | tar -C /usr/local/bin -xzf - \
  && chown root:root /usr/local/bin/fixuid \
  && chmod 4755 /usr/local/bin/fixuid \
  && mkdir -p /etc/fixuid \
  && printf "user: coder\ngroup: coder\n" > /etc/fixuid/config.yml

COPY files/entrypoint.sh /usr/bin/entrypoint.sh
RUN --mount=from=packages,src=/tmp,dst=/tmp/packages dpkg -i /tmp/packages/code-server*$(dpkg --print-architecture).deb

# Allow users to have scripts run on container startup to prepare workspace.
# https://github.com/coder/code-server/issues/5177
ENV ENTRYPOINTD=${HOME}/entrypoint.d

EXPOSE 3000
# This way, if someone sets $DOCKER_USER, docker-exec will still work as
# the uid will remain the same. note: only relevant if -u isn't passed to
# docker-run.
USER 1000
ENV USER=coder
WORKDIR /home/coder
ENTRYPOINT ["/usr/bin/entrypoint.sh", "--bind-addr", "0.0.0.0:3000", "."]