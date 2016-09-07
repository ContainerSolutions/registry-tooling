#!/bin/bash
set -e 
set -o pipefail

function configure_nodes {
  echo
  echo "Tidying up any old registry jobs"
  kubectl delete job create-certs &> /dev/null || true 

  echo
  echo "Creating new registry certificate"
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
  local rc=$?
  while [ $rc != 0 ]
  do
    sleep 1
    echo -n "."
    kubectl get --namespace=kube-system secret registry-cert &>/dev/null
    rc=$?
  done
  set -e
}

function configure_host {

  set +e
  kubectl get --namespace=kube-system secret registry-cert &> /dev/null
  local rc=$?
  if [ $rc != 0 ]; then
    echo "Registry certificate not found - expected it to be stored in the
kubernetes secret registry-cert."
    echo "Failed to configure host."
    return 1
  fi
  set -e

  echo "Adding certificate to local machine..."
  mkdir -p /etc/docker/certs.d/kube-registry.kube-system.svc.cluster.local:31000
  kubectl get --namespace=kube-system secret registry-cert \
    -o go-template --template '{{(index .data "ca.crt")}}' \
    | $base64_decode > \
    /etc/docker/certs.d/kube-registry.kube-system.svc.cluster.local:31000/ca.crt

  echo
  echo "Exposing registry via /etc/hosts"

  local schedulable_nodes=""
  if [ $SKR_EXTERNAL_IP ]; then
    schedulable_nodes=$SKR_EXTERNAL_IP
  else
    schedulable_nodes=$(kubectl get nodes -o template \
      --template='{{range.items}}{{if not .spec.unschedulable}}{{range.status.addresses}}{{if eq .type "ExternalIP"}}{{.address}} {{end}}{{end}}{{end}}{{end}}')
  fi

  for n in $schedulable_nodes 
  do
    k8s_node=$n
    break
  done

  # sed would be a better choice than ed, but it wants to create a temp file :(
  # turned off stderr here, as ed likes to write to it even in success case

  if [ -n "$k8s_node" ]; then
    printf 'g/kube-registry.kube-system.svc.cluster.local/d\nw\n' \
      | ed /etc/hosts 2> /dev/null

    echo "$k8s_node kube-registry.kube-system.svc.cluster.local #added by secure-kube-registry" >> /etc/hosts
  else
    echo
    echo "Failed to find external address for cluster" >&2
    echo "You can force the IP using the SKR_EXTERNAL_IP variable."
    echo "For example, if you're running minikube:"
    echo
    echo '$ export SKR_EXTERNAL_IP=$(minikube ip) && sudo -E ./start-registry.sh -l'
    return 2
  fi
  echo 
  echo "Succesfully configured localhost"
  return 0
}

#start main

if [[ $(id -u) -ne 0 ]]; then
  echo "This script expects to run as root i.e:"
  echo "sudo $0"
  exit 1
fi

#process args

local_only=false
print_help=false
base64_decode="base64 -d"
if [ "$(uname -s)" = "Darwin" ]; then
  base64_decode="base64 -D"
fi


while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in
    -l|--local)
      local_only=true
      ;;
    -h|--help)
      print_help=true
      ;;
    *)
      ;;
  esac
  shift
done

usage=$(cat <<'EOF'
This script will start a registry in your Kubernetes cluster and
configure it for secure access via TLS.

It does this by generating a TLS certificate and copying it to all nodes plus
setting /etc/hosts to resolve the registry name. The certificate will be stored
as a Kubernetes secret named registry-cert.

It will also (optionally) configure the current machine to access the registry
in the same way.

If you are concerned about the effects of editing /etc/hosts or do not
understand the above, please do not run this script.
EOF
)

options="Use -l or --local to configure localhost to access an existing registry."

if [ "$print_help" = true ]; then
  echo "$usage"
  echo 
  echo $options
  exit 0
fi

if [ "$local_only" = true ]; then
  echo "Setting up localhost to access registry"
  configure_host
  exit $?
fi

echo "$usage"

echo

while true
do
  read -r -p 'Do you want to continue? (y/n) ' choice
  case "$choice" in
    n|N) exit;;
    y|Y) break;;
    *) echo 'Response not valid';;
  esac
done

configure_nodes
echo 
echo 

while true
do
  read -r -p 'Do you want to add the certificate and modify /etc/hosts on the current machine? (y/n) ' choice
  case "$choice" in
    n|N) break;;
    y|Y) configure_host 
      break;;
    *) echo 'Response not valid';;
  esac
done

echo
echo "Set-up completed."
echo
echo "The registry certificate is stored in the secret registry-cert"
echo 
echo "The registry should shortly be available at:"
echo "kube-registry.kube-system.svc.cluster.local:31000"
echo
echo "Note that this port will need to be open in any firewalls."
echo "To open a firewall in GCE, try something like:"
echo "gcloud compute firewall-rules create expose-registry --allow TCP:31000"


