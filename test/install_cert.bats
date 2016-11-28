#!/usr/bin/env bats

@test "install via file" {
  
  #create a self-signed cert 
  cert_dir=$(mktemp -d /tmp/certs.XXXXXX)
  docker run -v "$cert_dir":/certs amouat/create-test-cert > /dev/null

  #start a registry on localhost
  docker run -v $cert_dir:/certs -p 5000 --name test-registry -e REGISTRY_HTTP_ADDR=:5000 -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/ca.crt -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key -d registry:2 > /dev/null

  sudo ../secure-registry.sh install-cert --cert-file "$cert_dir"/ca.crt --add-host 0.0.0.0 test-registry
  docker pull alpine:latest
  docker tag alpine:latest $(docker port test-registry)/test-image
  docker push $(docker port test-registry)/test-image

  #then run install-cert
  #test push/pull

  #can't use 127.0.0.1
  #need to mount cert in reg
}
