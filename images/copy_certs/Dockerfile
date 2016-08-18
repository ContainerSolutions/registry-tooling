FROM debian:jessie

RUN apt-get update && apt-get install ed \
    && rm -rf /var/lib/apt/lists/*
COPY kubectl /usr/local/bin/kubectl
COPY copy_certs.sh /
RUN chmod +x /copy_certs.sh
ENTRYPOINT /copy_certs.sh
