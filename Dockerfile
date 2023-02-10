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
    protobuf-compiler \
    libprotobuf-dev \
    libprotobuf-c-dev \
    gdb \
    cmake \
    pkg-config \
    python3 \
    python3-pip \
    git \
    gnupg \
    ca-certificates \
    curl \
    tzdata \
    libsodium-dev \
    && apt-get -y -q upgrade \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Gramine APT repository with public key
RUN echo "deb [arch=amd64 signed-by=/usr/share/keyrings/gramine-keyring.gpg] https://packages.gramineproject.io/ focal main" >> /etc/apt/sources.list.d/gramine.list \
    && curl -fsSLo /usr/share/keyrings/gramine-keyring.gpg https://packages.gramineproject.io/gramine-keyring.gpg

# Intel SGX APT repository with public key
RUN echo "deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu focal main" >> /etc/apt/sources.list.d/intel-sgx.list \
    && curl -fsSL https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | apt-key add -

# Install Gramine and Intel SGX dependencies
RUN apt-get update && apt-get install --no-install-recommends -qq -y \
    gramine \
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
RUN pip3 install -U mse-lib-sgx==0.15.0

WORKDIR /root

COPY Makefile .
COPY python.manifest.template .
COPY mse-run.sh /usr/local/bin/mse-run
COPY mse-test.sh /usr/local/bin/mse-test
COPY mse-memory.py /usr/local/bin/mse-memory
