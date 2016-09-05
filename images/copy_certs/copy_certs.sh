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
schedulable_nodes=$(kubectl get nodes -o template \
  --template='{{range.items}}{{if not .spec.unschedulable}}{{range.status.addresses}}{{if eq .type "InternalIP"}}{{.address}} {{end}}{{end}}{{end}}{{end}}')

#choosing a host at random isn't ideal, but I don't how to find the host for the pod
local_ip=$(shuf -e -n1 $schedulable_nodes)
echo "$local_ip kube-registry.kube-system.svc.cluster.local #Added by secure-kube-registry script" >> /hostfile
echo "Added entry"

