#!/bin/bash

# Turn on "strict mode"
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
# Not using -u as it upsets BATS :(
set -eo pipefail
unset CDPATH
IFS=$'\n\t'

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

  for job in $(kubectl get jobs -o go-template --template '{{range .items}}{{.metadata.name}}
    {{end}}')
  do
    if [[ $job = copy-certs* ]]; then
      kubectl delete job "$job"
    fi
  done
  tmp_file=$(mktemp)
  kubectl get nodes -o go-template-file --template ./k8s/copy-certs-templ.yaml > "$tmp_file"
  kubectl create -f "$tmp_file"
  rm "$tmp_file"

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
  while [[ $rc != 0 ]]
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
  if [[ $rc != 0 ]]; then
    echo "Registry certificate not found - expected it to be stored in the
Kubernetes secret registry-cert."
    echo "Failed to configure host."
    return 1
  fi
  set -e

  if "$on_mac"; then

    echo "Assuming running Docker for Mac - adding certificate to internal VM"
    tmp_file=$(mktemp /tmp/cert.XXXXXX)
    chmod go+rw "$tmp_file"
    kubectl get --namespace=kube-system secret registry-cert \
            -o go-template --template '{{(index .data "ca.crt")}}' \
            | base64 -D > "$tmp_file"
    docker run --rm -v "$tmp_file":/data/cert -v /etc/docker:/data/docker alpine \
            sh -c "mkdir -p /data/docker/certs.d/$registry_host\:$registry_port &&
                   cp /data/cert /data/docker/certs.d/$registry_host\:$registry_port/ca.crt"
    rm "$tmp_file"

  else #on Linux

    echo "Adding certificate to local machine..."
    mkdir -p "/etc/docker/certs.d/${registry_host}:$registry_port"
    kubectl get --namespace=kube-system secret registry-cert \
      -o go-template --template '{{(index .data "ca.crt")}}' \
      | base64 -d > \
      "/etc/docker/certs.d/${registry_host}:$registry_port/ca.crt"
  fi

  echo
  echo "Exposing registry via /etc/hosts"

  local schedulable_nodes=""
  if [[ "$SKR_EXTERNAL_IP" ]]; then
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

  if [[ -n "$k8s_node" ]]; then
    printf "g/%s/d\nw\n" "$registry_host" \
      | ed /etc/hosts 2> /dev/null

    echo "$k8s_node $registry_host #added by secure-kube-registry" >> /etc/hosts
  else
    echo
    echo "Failed to find external address for cluster" >&2
    echo "You can force the IP using the SKR_EXTERNAL_IP variable."
    echo "For example, if you're running minikube:"
    echo
    echo '$ export SKR_EXTERNAL_IP=$(minikube ip) && sudo -E' "$0 install-cert"
    return 2
  fi
  echo 
  echo "Succesfully configured localhost"
  return 0
}

function install_k8s_registry {

  k8s_usage=$(cat <<EOF 

Installs a Docker registry in your Kubernetes cluster and configures it
for secure access via TLS.

This involves generating a TLS certificate and copying it to all nodes, plus
setting /etc/hosts on the nodes to resolve the registry name. The certificate
will be stored as a Kubernetes secret named "registry-cert".

If you are concerned about the effects of editing /etc/hosts or do not
understand the above, please do not use this tool.

EOF
  )
  echo "$k8s_usage"

  echo

  if [[ "$require_confirm" = true ]]; then
    while true
    do
      read -r -p 'Do you want to continue? (y/n) ' choice
      case "$choice" in
        n|N) exit;;
        y|Y) break;;
        *) echo 'Response not valid';;
      esac
    done
  fi

  configure_nodes
  echo 
  echo 

  echo
  completed=$(cat <<-EOF
Set-up completed

The registry certificate is stored in the secret "registry-cert"

The registry should shortly be available to the cluster at:
${registry_host}:$registry_port

Note that this port will need to be open in any firewalls.
To open a firewall in GCE, try:
gcloud compute firewall-rules create expose-registry --allow TCP:$registry_port

Use install-cert command to configure a local Docker daemon to access the 
registry:
$ sudo $0 install-cert

Or on minikube:
$ echo 'export SKR_EXTERNAL_IP=$(minikube ip) && sudo -E' "$0 install-cert"
EOF
  )
  echo "$completed"
}

function process_k8s_args {

  while [[ $# -gt 0 ]]
  do
    key="$1"

    case $key in
      -y|--yes)
        require_confirm=false
        ;;
      *)
        ;;
    esac
    shift
  done
}

function process_cert_args {

  while [[ $# -gt 0 ]]
  do
    key="$1"

    case $key in
      -y|--yes)
        require_confirm=false
        ;;
      *)
        ;;
    esac
    shift
  done
}

function install_cert {
  if [[ $(id -u) -ne 0 ]]; then
    # could use docker to circumvent this issue
    echo "Installing a certificate requires root privileges i.e:"
    echo 
    echo "$ sudo $0 $args"
    exit 1
  fi
  echo "Setting up localhost to access registry"
  configure_host
  return $?
}

#start main

registry_host="kube-registry.kube-system.svc.cluster.local"
registry_port=31000

on_mac=false
if [[ "$(uname -s)" = "Darwin" ]]; then
  on_mac=true
fi

#change to directory with script so we can reach deps
#https://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in
src_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$src_dir"

#process args

args=$@
require_confirm=true


usage=$(cat <<EOF

Tool for working with Docker registries, especially those using self-signed
certificates. 
EOF
)

commands=$(cat <<EOF
Commands:

  install-cert    install the registry certificate on the current Docker 
                  engine.
  install-k8s-reg install a secure registy on a Kubernetes cluster or minikube.

Options:

install-cert
  -y --yes               proceed without asking for confirmation
  --cert-file            path or URL for registry certificate
  --k8s-secret SECRET    retrieve the certificate from the named secret    
  --add-host IP NAME     add an entry in /etc/hosts for the registry with IP
                         and NAME

install-k8s-reg
  --name NAME     sets the name of the registry

EOF
)

function print_help {
  echo "$usage"
  echo 
  echo "$commands"
}

# First arg must be command or --help

if [[ $# -gt 0 ]]; then
  case $1 in
    install-cert)
      process_cert_args "$@"
      install_cert
      exit $?
      ;;
    install-k8s-reg)
      process_k8s_args "$@"
      install_k8s_registry
      exit $?
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      printf 'FATAL: Unknown command: %s\n' "$1" >&2
      print_help
      exit 1
      ;;
  esac
  shift
fi

# No commands given
print_help
exit 1
