# Build gramine from main branch
FROM ubuntu:20.04 as gramine

USER root
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /root

RUN apt-get update && apt-get install --no-install-recommends -qq -y \
    git \
    build-essential \
    protobuf-compiler \
    libprotobuf-dev \
    libprotobuf-c-dev \
    protobuf-c-compiler \
    autoconf \
    bison \
    gawk \
    nasm \
    ninja-build \
    pkg-config \
    python3 \
    python3-cryptography \
    python3-click \
    python3-jinja2 \
    python3-pip \
    python3-protobuf \
    python3-pyelftools \
    wget \
    linux-headers-$(uname -r) && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    python3 -m pip install 'meson>=0.56' 'tomli>=1.1.0' 'tomli-w>=0.4.0'

# TODO: specify the proper commit to checkout
RUN git clone https://github.com/gramineproject/gramine
WORKDIR /root/gramine
RUN meson setup build/ --buildtype=release -Ddirect=enabled -Dsgx=enabled && \
    ninja -C build/ && \
    ninja -C build/ install

# Build the final image
FROM ubuntu:20.04

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV TS=Etc/UTC
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONPYCACHEPREFIX "/tmp"
ENV PYTHONUNBUFFERED 1

WORKDIR /root

RUN apt-get update && apt-get install --no-install-recommends -qq -y \
    build-essential \
    pkg-config \
    libprotobuf-c-dev \
    python3 \
    python3-pip \
    python3-click \
    python3-jinja2 \
    python3-pyelftools \
    gnupg \
    ca-certificates \
    curl \
    tzdata \
    && apt-get -y -q upgrade \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && pip install 'tomli>=1.1.0' 'tomli-w>=0.4.0'

# Intel SGX APT repository with public key
RUN echo "deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu focal main" >> /etc/apt/sources.list.d/intel-sgx.list \
    && curl -fsSL https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | apt-key add -

COPY --from=gramine /usr/local/bin/gramine-* /usr/bin/
COPY --from=gramine /usr/local/lib/python3.8/dist-packages/graminelibos  /usr/local/lib/python3.8/dist-packages/graminelibos
COPY --from=gramine /usr/local/lib/x86_64-linux-gnu/gramine/ /usr/local/lib/x86_64-linux-gnu/gramine/

# Install Intel SGX dependencies
RUN apt-get update && apt-get install --no-install-recommends -qq -y \
    libsgx-launch \
    libsgx-urts \
    libsgx-quote-ex \
    libsgx-epid \
    libsgx-dcap-ql \
    libsgx-dcap-quote-verify \
    linux-base-sgx \
    libsgx-dcap-default-qpl \
    sgx-aesm-service \
    libsgx-aesm-quote-ex-plugin \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/intel

ARG SGX_SDK_VERSION=2.18
ARG SGX_SDK_INSTALLER=sgx_linux_x64_sdk_2.18.100.3.bin

# Install Intel SGX SDK
RUN curl -fsSLo $SGX_SDK_INSTALLER https://download.01.org/intel-sgx/sgx-linux/$SGX_SDK_VERSION/distro/ubuntu20.04-server/$SGX_SDK_INSTALLER \
    && chmod +x  $SGX_SDK_INSTALLER \
    && echo "yes" | ./$SGX_SDK_INSTALLER \
    && rm $SGX_SDK_INSTALLER

# Install MSE Enclave library
RUN pip3 install -U mse-lib-sgx==1.0

WORKDIR /root

COPY Makefile .
COPY python.manifest.template .
COPY mse-run.sh /usr/local/bin/mse-run
COPY mse-test.sh /usr/local/bin/mse-test
COPY mse-memory.py /usr/local/bin/mse-memory
