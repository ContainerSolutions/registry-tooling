#!/usr/bin/env bats

function setup { 
  minikube start --vm-driver=kvm > /dev/null || true
  run kubectl cluster-info > /dev/null
  while [[ "$status" != 0 ]]
  do
    sleep 1
    run kubectl cluster-info > /dev/null
  done
}

@test "happy path" {
  ../reg-tool.sh install-k8s-reg -y > /dev/null
  sudo ../reg-tool.sh install-cert --add-host $(minikube ip) > /dev/null
  docker pull alpine:latest
  docker tag alpine:latest kube-registry.kube-system.svc.cluster.local:31000/alpine:latest
  # this typically fails, presumably due to caching of DNS in lib used by Docker
  # Give DNS 5 secs
  sleep 5
  docker push kube-registry.kube-system.svc.cluster.local:31000/alpine:latest > /dev/null
  kubectl delete deployment test-deploy > /dev/null || true
  kubectl run test-deploy --image kube-registry.kube-system.svc.cluster.local:31000/alpine:latest --command sleep 100 > /dev/null
  #need to check don't get pull error here
  kubectl delete deployment test-deploy
}

