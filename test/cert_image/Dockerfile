FROM debian:jessie

RUN apt-get update && export TERM=xterm && \
    apt-get install -y openssl \
    && rm -rf /var/lib/apt/lists/*

COPY create_cert.sh /
COPY in.req /
RUN chmod +x /create_cert.sh

ENTRYPOINT /create_cert.sh
