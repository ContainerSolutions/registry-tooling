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
  kubectl create -f k8s/create-certs.yaml &> /dev/null || true

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

    {{end}}') # blank line is important
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

function get_cert_from_k8s {
  local tmp_file="$1"

  base64_arg="-d"
  if "$on_mac"; then
    base64_arg="-D"
  fi

  set +e
  kubectl get --namespace="$k8s_secret_ns" secret "$k8s_secret" \
            -o go-template --template '{{(index .data "ca.crt")}}' \
            | exec base64 $base64_arg > "$tmp_file"
  local rc=$?
  if [[ $rc != 0 ]]; then
    echo "Registry certificate not found - expected it to be stored in the
Kubernetes secret $k8s_secret in namespace $k8s_secret_ns"
    echo "Failed to configure host."
    exit 1
  fi
  set -e
}

function copy_cert {

  cert_file=$1

  if "$on_mac"; then

    echo "Assuming running Docker for Mac - adding certificate to Docker keychain"
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$cert_file"
    echo 
    echo "Certificate added - restart Docker for Mac to take effect"

  else #on Linux

    echo "Adding certificate to local machine..."
    mkdir -p "/etc/docker/certs.d/${registry_host}"
    cp "$cert_file"  "/etc/docker/certs.d/${registry_host}/ca.crt"
  fi
}

function add_to_etc_hosts {

  echo
  echo "Exposing registry via /etc/hosts"


  # sed would be a better choice than ed, but it wants to create a temp file :(
  # turned off stderr here, as ed likes to write to it even in success case

  if [[ -n "$add_host_ip" ]]; then
    printf "g/%s/d\nw\n" "$add_host_name" \
      | ed /etc/hosts 2> /dev/null

    echo "$add_host_ip $add_host_name #added by secure-kube-registry" >> /etc/hosts
  else
    echo
    echo "Failed to find external address for cluster" >&2
    echo "Please set the IP address explicitly."
    echo "For example, if you're running minikube:"
    echo
    echo "$ sudo $0 install-cert" '--add-host $(minikube ip)'
    exit 2
  fi
  echo 
  echo "Successfully configured localhost"
  return 0
}

function get_ip_from_k8s {

  add_host_ip=""
  local schedulable_nodes=""
  schedulable_nodes="$(kubectl get nodes -o template \
    --template='{{range.items}}{{if not .spec.unschedulable}}{{range.status.addresses}}{{if eq .type "ExternalIP"}}{{.address}} {{end}}{{end}}{{end}}{{end}}')" 

  for n in $schedulable_nodes 
  do
    add_host_ip=$n
    break
  done

  if [[ -z "$add_host_ip" ]]; then
    echo
    echo "Failed to discover ip for registry."
    echo "Please specify explicitly with --add-host e.g:"
    echo
    echo "  $0 --add-host 192.168.0.3 my-registry"
    exit 1
  fi
}


function install_k8s_registry {

  k8s_usage=$(cat <<EOF 

Installs a Docker registry in your Kubernetes cluster and configures it
for secure access via TLS.

This involves generating a TLS certificate and copying it to all nodes, plus
setting /etc/hosts on the nodes to resolve the registry name. The certificate
will be stored as a Kubernetes secret named "registry-cert" in the kube-system
namespace.

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
  # TODO Add check for no port and set to 80
  completed=$(cat <<-EOF
Set-up completed

The registry certificate is stored in the secret "registry-cert" in the
kube-system namespace.

The registry should shortly be available to the cluster at:
${registry_host}

Note that this port will need to be open in any firewalls.
To open a firewall in GCE, try:
gcloud compute firewall-rules create expose-registry --allow TCP:${registry_port}

Use install-cert command to configure a local Docker daemon to access the 
registry:
$ sudo $0 install-cert

Or on minikube:
$ sudo $0 install-cert --add-host \$(minikube ip)
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
#      -n|--name)
#        registry_host="$2"
#        shift
#        ;;
      *)
        ;;
    esac
    shift
  done

  if [[ $registry_host == *":"* ]]; then
    registry_port=${registry_host##*:} 
  else
    registry_port="80"
  fi
}

function process_cert_args {

  while [[ $# -gt 0 ]]
  do
    key="$1"

    case $key in
      -y|--yes)
        require_confirm=false
        ;;
      --cert-file)
        file_path="$2"

        if [[ -z "$file_path" ]]; then
          echo "No certificate file provided"
          exit 1
        fi 
        
        shift
        ;;
      --k8s-secret)
        k8s_secret="$2"
        k8s_secret_set=true

        if [[ -z "$k8s_secret" ]]; then
          echo "No secret provided"
          exit 1
        fi 
        shift
        ;;
      --reg-name)
        registry_host=$2
        if [[ -z "$registry_host" ]]; then
          echo "No registry name provided"
          exit 1
        fi 
        shift
        ;;
      --k8s-secret-ns)
        k8s_secret_ns="$2"
        if [[ -z "$k8s_secret_ns" ]]; then
          echo "No namespace provided"
          exit 1
        fi 
        shift
        ;;
      --add-host)
        add_host_ip="$2"
        if [[ -z $add_host_ip || ${add_host_ip:0:1} == "-" ]]; then
          # ip/name not specified; ask k8s
          add_host_ip=""
          add_host_name=${default_host%%:*}
          echo "Assuming host name $add_host_name"
          get_ip_from_k8s
          continue
        fi 
        add_host_name="$3"
        if [[ -z $add_host_name ]]; then
          add_host_name=${default_host%%:*}
          echo "Assuming host name $add_host_name"
          shift
          break
        fi
        shift
        shift
        ;;
      *)
        ;;
    esac
    shift
  done
}

#TODO kill env var
#Pull out IP finding
#rewire


function install_cert {

  tmp_file=$(mktemp /tmp/cert.XXXXXX)

  if [[ $(id -u) -ne 0 ]]; then
    # could use docker to circumvent this issue
    echo "Installing a certificate requires root privileges i.e:"
    echo 
    echo "$ sudo $0 $args"
    exit 1
  fi
  if [[ -n "$file_path" && -n "$k8s_secret_set" ]]; then
    echo "Cannot set both file path and kubernetes secret"
    exit 1
  elif [[ -n "$file_path" ]]; then
    if [[ "$file_path" == http://* || "$file_path" == https://* ]]; then
      command -v curl >/dev/null 2>&1 || { 
        echo >&2 "Install curl to get certificates from URL"
        exit 1 
      }
      echo "Retrieving certificate from $file_path"
      curl -sSL "$file_path" > "$tmp_file" 
    else
      cp "$file_path" "$tmp_file"
    fi

  else 
    if [[ -z "$k8s_secret_ns" ]]; then
      #test if secret in default ns or kube-system
      set +e
      kubectl get secret "$k8s_secret" --namespace=kube-system > /dev/null
      local rc=$?
      if [[ $rc == 0 ]]; then
        k8s_secret_ns="kube-system"
      else
        kubectl get secret "$k8s_secret" --namespace= > /dev/null
        rc=$?
        if [[ $rc == 0 ]]; then
          k8s_secret_ns=
        else
          echo "Cannot find secret $k8s_secret in kube-system or default namespace"
          exit 1
        fi
      fi
      set -e

    fi
    echo "Retrieving certificate from Kubernetes secret $k8s_secret"
    if [[ -n $k8s_secret_ns ]]; then
      echo "in namespace $k8s_secret_ns"
    fi
    get_cert_from_k8s "$tmp_file"
  fi

  echo "Installing certificate"
  copy_cert "$tmp_file"


  if [[ -n "$add_host_ip" ]]; then
    #probably put check here
    add_to_etc_hosts
  fi

  return $?
}

#start main

default_host="kube-registry.kube-system.svc.cluster.local:31000"
registry_host=$default_host
registry_port='' #parsed from host later

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
file_path=
k8s_secret="registry-cert"
k8s_secret_set=
k8s_secret_ns=
add_host_ip=

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
  --cert-file FILE       path or URL for registry certificate
  --reg-name NAME        full name of the registry including port. Defaults to 
                         kube-registry.kube-system.svc.cluster.local:31000
  --k8s-secret SECRET    retrieve the certificate from the named secret.
                         Defaults to registry-cert.
  --k8s-secret-ns NS     use the namespace NS when retrieving the secret
  --add-host IP NAME     add an entry in /etc/hosts for the registry with IP
                         and NAME

install-k8s-reg
  -y --yes               proceed without asking for confirmation

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
