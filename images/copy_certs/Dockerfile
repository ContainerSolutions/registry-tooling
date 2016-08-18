FROM debian:jessie

RUN apt-get update && apt-get install -y \
      ed curl \
    && rm -rf /var/lib/apt/lists/*
RUN curl -o /usr/local/bin/kubectl -sSL https://storage.googleapis.com/kubernetes-release/release/v1.3.4/bin/linux/amd64/kubectl
RUN chmod +x /usr/local/bin/kubectl 
COPY copy_certs.sh /
RUN chmod +x /copy_certs.sh
ENTRYPOINT /copy_certs.sh
