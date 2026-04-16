FROM debian:stable-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    lcov \
    libssl-dev \
    libpam0g-dev \
    libwrap0-dev \
    libjson-xs-perl \
    llvm \
    zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

COPY . /target
WORKDIR /target

ENV NAME=proftpd \
    INTERVAL=60 \
    OUTPUT_DIR=/coverage_data \
    TRIGGER_SIGNAL=USR2 \
    LOG=/dev/null \
    LOG_ERR=/dev/null

RUN chmod +x ./cov.sh && \
    ./configure CFLAGS="--coverage -O0 -g" LDFLAGS="--coverage" --enable-devel=nodaemon:nofork && \
    make -j"$(nproc)" && \
    chmod -R 777 /target

RUN groupadd ubuntu && \
    useradd -rm -d /home/ubuntu -s /bin/bash -g ubuntu -G sudo -u 1000 ubuntu -p "$(openssl passwd -1 ubuntu)" && \
    mkdir /home/ubuntu/ftpshare && \
    chown -R ubuntu:ubuntu /home/ubuntu/ftpshare && \
    chmod -R 777 /tmp

CMD ["./cov.sh"]
