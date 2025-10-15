FROM mcr.microsoft.com/devcontainers/base:ubuntu

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    curl wget git vim jq ca-certificates gnupg lsb-release \
    apache2-utils build-essential libssl-dev python3-pip ansible

RUN cd /tmp && git clone https://github.com/wg/wrk.git && cd wrk && make && cp wrk /usr/local/bin/ && cd / && rm -rf /tmp/wrk

RUN wget -q https://github.com/fullstorydev/grpcurl/releases/download/v1.8.9/grpcurl_1.8.9_linux_x86_64.tar.gz && \
    tar -xzf grpcurl_1.8.9_linux_x86_64.tar.gz && mv grpcurl /usr/local/bin/ && rm grpcurl_1.8.9_linux_x86_64.tar.gz

RUN wget -q https://github.com/bojand/ghz/releases/download/v0.117.0/ghz-linux-x86_64.tar.gz && \
    tar -xzf ghz-linux-x86_64.tar.gz && mv ghz /usr/local/bin/ && rm ghz-linux-x86_64.tar.gz

RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
# https://github.com/hotheadhacker/seedbox-lite