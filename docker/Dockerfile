# Pinned in dependencies/dependencies.lock.json: container_images.ubuntu_22_04.
FROM ubuntu@sha256:0d779ea97881505f5ef0039336ee85edba27519bdba968c284c86ee066a973c8

LABEL org.opencontainers.image.title="retroSoC development environment"
LABEL org.opencontainers.image.description="Lock-pinned open-source retroSoC regression tools"
LABEL org.opencontainers.image.base.name="ubuntu:22.04"

ENV DEBIAN_FRONTEND=noninteractive
ENV RETROSOC_DEVELOPMENT_CACHE=/opt/retrosoc/development

RUN apt-get update -qq \
    && apt-get install --no-install-recommends --yes \
        bzip2 \
        ca-certificates \
        ccache \
        clang-format-14 \
        g++ \
        git \
        libfl2 \
        libgoogle-perftools4 \
        libunwind8 \
        make \
        mold \
        numactl \
        python3 \
        python3-pip \
        python3-venv \
        xz-utils \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/retrosoc

COPY dependencies/dependencies.lock.json dependencies/dependencies.lock.json
COPY requirements/build.txt requirements/build.txt
COPY requirements/ci.txt requirements/ci.txt
COPY scripts/dependency_lock.py scripts/dependency_lock.py
COPY scripts/development_environment.py scripts/development_environment.py
COPY scripts/install_toolchain.py scripts/install_toolchain.py
COPY scripts/setup_helpers.py scripts/setup_helpers.py

RUN python3 scripts/development_environment.py \
        --root /opt/retrosoc \
        --cache "$RETROSOC_DEVELOPMENT_CACHE" \
        bootstrap

COPY docker/entrypoint.sh /usr/local/bin/retrosoc-entrypoint
RUN chmod 0755 /usr/local/bin/retrosoc-entrypoint

WORKDIR /workspace/retrosoc
ENTRYPOINT ["/usr/local/bin/retrosoc-entrypoint"]
CMD ["bash"]
