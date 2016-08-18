#!/bin/bash
set -e 
set -o pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "This script expects to run as root i.e:"
  echo "sudo $0"
  exit 1
fi

echo "Deleting any old certs..."
kubectl delete job create-certs copy-certs &> /dev/null || true 

echo
echo "Creating new certs"
kubectl create -f k8s/create-certs.yaml

echo
echo -n "Waiting for job to complete"
while [[ $(kubectl get job create-certs \
  -o go-template --template "{{.status.succeeded}}") != 1 ]]
do
  sleep 1
  echo -n "."
done

echo
echo "Copying certs to nodes"
kubectl create -f k8s/copy-certs.yaml

echo
echo "Removing any old registry and starting new one..."
kubectl delete rc --namespace=kube-system kube-registry &> /dev/null || true 
kubectl create -f k8s/reg_controller.yaml
kubectl delete svc --namespace=kube-system kube-registry &> /dev/null || true 
kubectl create -f k8s/reg_service.yaml

#wait for cert to become available
echo
echo -n "Waiting for cert to become available"
set +e
kubectl get --namespace=kube-system secret registry-cert &> /dev/null
rc=$?
while [ $rc != 0 ]
do
  sleep 1
  echo -n "."
  kubectl get --namespace=kube-system secret registry-cert &>/dev/null
  rc=$?
done
set -e

echo 
echo "Adding certificate to local machine..."
kubectl get --namespace=kube-system secret registry-cert \
  -o go-template --template '{{(index .data "ca.crt")}}' \
  | base64 -d > \
  /etc/docker/certs.d/kube-registry.kube-system.svc.cluster.local:31000/ca.crt

echo
echo "Exposing registry via /etc/hosts"

#make resolvable on local machine
#this is very hacky 
K8S_MASTER=$(kubectl cluster-info | \
    sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" | \
    sed -n 's/Kubernetes master is running at https:\/\/\([^:]*\):.*/\1/p')

# sed would be a better choice than ed, but it wants to create a temp file :(
# turned off stderr here, as ed likes to write to it even in success case
printf 'g/kube-registry.kube-system.svc.cluster.local/d\nw\n' \
  | ed /etc/hosts 2> /dev/null

echo "$K8S_MASTER kube-registry.kube-system.svc.cluster.local" >> /etc/hosts

echo
echo "Set-up completed."
echo
echo "The registry should shortly be available at:"
echo "kube-registry.kube-system.svc.cluster.local:31000"
