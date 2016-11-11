#!/bin/bash

set -e

minikube start --vm-driver=kvm
set +e
kubectl cluster-info > /dev/null
rc=$?
while [[ $rc != 0 ]]
do
  sleep 1
  echo -n "."
  kubectl cluster-info > /dev/null
  rc=$?
done
set -e

../secure-registry.sh -k -y
export SKR_EXTERNAL_IP=$(minikube ip) && sudo -E ../secure-registry.sh -c
docker pull alpine:latest
docker tag alpine:latest kube-registry.kube-system.svc.cluster.local:31000/alpine:latest
docker push kube-registry.kube-system.svc.cluster.local:31000/alpine:latest
kubectl delete deployment test-deploy || true
kubectl run test-deploy --image kube-registry.kube-system.svc.cluster.local:31000/alpine:latest --command sleep 100
#need to check don't get pull error here
kubectl delete deployment test-deploy

echo
echo "Passed Test"
