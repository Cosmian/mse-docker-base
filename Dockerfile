FROM ubuntu:22.04

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV TS=Etc/UTC
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONPYCACHEPREFIX "/tmp"
ENV PYTHONUNBUFFERED 1

RUN echo 'APT::Install-Suggests "0";' >> /etc/apt/apt.conf.d/00-docker
RUN echo 'APT::Install-Recommends "0";' >> /etc/apt/apt.conf.d/00-docker
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    pkg-config \
    curl \
    python3 \
    python3-pip \
    python3-venv \
    gnupg \
    ca-certificates \
    curl \
    tzdata \
    wget && \
    rm -rf /var/lib/apt/lists/*

# Gramine APT repository
RUN curl -fsSLo /usr/share/keyrings/gramine-keyring.gpg https://packages.gramineproject.io/gramine-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/gramine-keyring.gpg] https://packages.gramineproject.io/ jammy main" \
    | tee /etc/apt/sources.list.d/gramine.list

# Intel SGX APT repository
RUN curl -fsSLo /usr/share/keyrings/intel-sgx-deb.asc https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-sgx-deb.asc] https://download.01.org/intel-sgx/sgx_repo/ubuntu jammy main" \
    | tee /etc/apt/sources.list.d/intel-sgx.list


# Install Intel SGX dependencies and Gramine
RUN apt-get update && apt-get install -y \
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
    gramine && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/intel

ARG SGX_SDK_VERSION=2.19
ARG SGX_SDK_INSTALLER=sgx_linux_x64_sdk_2.19.100.3.bin

# Install Intel SGX SDK
RUN curl -fsSLo $SGX_SDK_INSTALLER https://download.01.org/intel-sgx/sgx-linux/$SGX_SDK_VERSION/distro/ubuntu22.04-server/$SGX_SDK_INSTALLER \
    && chmod +x  $SGX_SDK_INSTALLER \
    && echo "yes" | ./$SGX_SDK_INSTALLER \
    && rm $SGX_SDK_INSTALLER

# Configure virtualenv
ENV GRAMINE_VENV=/opt/venv
RUN python3 -m venv $GRAMINE_VENV

# Install MSE Enclave library
RUN . "$GRAMINE_VENV/bin/activate" && \
    python3 -m pip install -U pip setuptools && \
    python3 -m pip install -U mse-lib-sgx==3.0a1

WORKDIR /root

COPY Makefile .
COPY python.manifest.template .
COPY mse-run.sh /usr/local/bin/mse-run
COPY mse-test.sh /usr/local/bin/mse-test
COPY mse-memory.py /usr/local/bin/mse-memory
