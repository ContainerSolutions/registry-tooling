FROM debian:jessie

RUN apt-get update && export TERM=xterm && \
    apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*

COPY kubectl /usr/local/bin/kubectl

COPY create_certs.sh /
COPY in.req /
RUN chmod +x /create_certs.sh

ENTRYPOINT /create_certs.sh
