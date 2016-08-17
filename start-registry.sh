#!/bin/bash
set -e 
set -o pipefail

kubectl delete job create-certs copy-certs || true
kubectl create -f k8s/create-certs.yaml
kubectl create -f k8s/copy-certs.yaml
kubectl delete rc --namespace=kube-system kube-registry || true
kubectl create -f k8s/reg_controller.yaml
kubectl delete svc --namespace=kube-system kube-registry || true
kubectl create -f k8s/reg_service.yaml

#wait for cert to become available
echo -n "waiting for cert"
set +e
kubectl get --namespace=kube-system secret registry-cert 2>/dev/null
rc=$?
while [ $rc != 0 ]
do
  sleep 1
  echo -n "."
  kubectl get --namespace=kube-system secret registry-cert 2>/dev/null
  rc=$?
done
set -e

echo "\n"
#write out registry cert to local machine
kubectl get --namespace=kube-system secret registry-cert -o go-template --template '{{(index .data "ca.crt")}}' | base64 -d > /etc/docker/certs.d/kube-registry.kube-system.svc.cluster.local:31000/ca.crt

echo "added cert"

#make resolvable on local machine
#this is very hacky 
K8S_MASTER=$(kubectl cluster-info | \
    sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" | \
    sed -n 's/Kubernetes master is running at https:\/\/\([^:]*\):.*/\1/p')

# sed would be a better choice than ed, but it wants to create a temp file :(
printf 'g/kube-registry.kube-system.svc.cluster.local/d\nw\n' | ed /etc/hosts
echo "$K8S_MASTER kube-registry.kube-system.svc.cluster.local" >> /etc/hosts

echo "configured /etc/hosts"
