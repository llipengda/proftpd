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
    ./configure CFLAGS="--coverage -O0 -g" LDFLAGS="--coverage" && \
    make -j"$(nproc)" && \
    chmod -R 777 /target

CMD ["./cov.sh"]
