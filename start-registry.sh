#!/bin/bash
set -e 
set -o pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "This script expects to run as root i.e:"
  echo "sudo $0"
  exit 1
fi

echo "Remove any old jobs"
kubectl delete job create-certs &> /dev/null || true 

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

for job in $(kubectl get jobs -o go-template --template '{{range .items}}{{.metadata.name}} {{end}}')
do
  if [[ $job == copy-certs* ]]; then
    kubectl delete job $job
  fi
done
kubectl get nodes -o go-template-file --template ./k8s/copy-certs-templ.yaml > /tmp/copy-certs.yaml
kubectl create -f /tmp/copy-certs.yaml

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

schedulable_nodes=$(kubectl get nodes -o template \
  --template='{{range.items}}{{if not .spec.unschedulable}}{{range.status.addresses}}{{if eq .type "ExternalIP"}}{{.address}} {{end}}{{end}}{{end}}{{end}}')

if [ -z "$schedulable_nodes" ]; then
  schedulable_nodes=$(kubectl get nodes -o template \
    --template='{{range.items}}{{if not .spec.unschedulable}}{{range.status.addresses}}{{if eq .type "LegacyHostIP"}}{{.address}} {{end}}{{end}}{{end}}{{end}}')
fi

for n in $schedulable_nodes 
do
  K8S_NODE=$n
  break
done

# sed would be a better choice than ed, but it wants to create a temp file :(
# turned off stderr here, as ed likes to write to it even in success case

if [ -n "$K8S_NODE" ]; then
  printf 'g/kube-registry.kube-system.svc.cluster.local/d\nw\n' \
    | ed /etc/hosts 2> /dev/null

  echo "$K8S_NODE kube-registry.kube-system.svc.cluster.local" >> /etc/hosts
else
  echo "Failed to find external address for cluster" >&2
fi

echo
echo "Set-up completed."
echo
echo "The registry should shortly be available at:"
echo "kube-registry.kube-system.svc.cluster.local:31000"
echo
echo "Note that this port will need to be open in any firewalls."
echo "To open a firewall in GCE, try something like:"
echo "gcloud compute --project PROJECT firewall-rules create expose-registry --allow TCP:31000"
