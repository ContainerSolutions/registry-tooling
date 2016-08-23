#!/bin/bash
set -e
set -o pipefail


mkdir --parents /etc/docker/certs.d/kube-registry.kube-system.svc.cluster.local:31000/
echo "copying certs"
kubectl get secret registry-cert \
  -o go-template --template '{{(index .data "ca.crt")}}' \
  | base64 -d \
  > /etc/docker/certs.d/kube-registry.kube-system.svc.cluster.local:31000/ca.crt
echo "Sucessfully copied certs"

echo "Adding entry to /etc/hosts"
# sed would be a better choice than ed, but it wants to create a temp file :(
printf 'g/kube-registry.kube-system.svc.cluster.local/d\nw\n' | ed /hostfile
#ideally we don't want to use a 127 address as the insecure registry logic gets triggered
LOCAL_IP=$(hostname --ip-address)
echo "$LOCAL_IP kube-registry.kube-system.svc.cluster.local #Added by secure-kube-registry script" >> /hostfile
echo "Added entry"

