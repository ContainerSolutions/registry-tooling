FROM debian:jessie

RUN apt-get update && export TERM=xterm && \
    apt-get install -y openssl curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -o /usr/local/bin/kubectl -sSL https://storage.googleapis.com/kubernetes-release/release/v1.3.4/bin/linux/amd64/kubectl
RUN chmod +x /usr/local/bin/kubectl

COPY create_certs.sh /
COPY in.req /
RUN chmod +x /create_certs.sh

ENTRYPOINT /create_certs.sh
