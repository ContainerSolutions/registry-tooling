#!/bin/bash
set -e
set -o pipefail

mkdir certs

#get rid of any old certs; careful here, maybe require flag?
kubectl delete secret registry-cert || true
kubectl delete secret --namespace=kube-system registry-cert || true
kubectl delete secret --namespace=kube-system registry-key || true

openssl req -config /in.req -newkey rsa:4096 -nodes -sha256 -keyout certs/domain.key -x509 -days 265 -out certs/ca.crt
#put the public key in both the default and kube-system namespaces
kubectl create secret generic registry-cert --from-file=./certs/ca.crt 
kubectl create --namespace=kube-system secret generic registry-cert --from-file=./certs/ca.crt 
kubectl create --namespace=kube-system secret generic registry-key --from-file=./certs/domain.key
