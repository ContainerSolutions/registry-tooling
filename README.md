# Registry Tooling

Tools for working with Docker registries, especially those using self-signed
certificates.

Currently there are two features:

 - [configuring local clients](https://github.com/ContainerSolutions/registry-tooling#configuring-a-client-to-access-a-registry-with-a-self-signed-certificate) to access a registry secured with a self-signed
   cert
 - easy [installation of a secure Docker registry](https://github.com/ContainerSolutions/registry-tooling#installing-a-secure-reigstry-on-kubernetes)  onto a Kubernetes cluster
   using a self-signed certificate

## Installation

```
$ git clone https://github.com/ContainerSolutions/registry-tooling.git
```

At the moment there is no install script, just run the `reg-tool.sh` script from
the directory you downloaded it into. 

## Configuring a Client to Access a Registry with a Self-signed Certificate

If you have a registry running with a self-signed certificate, it can be a pain
to provide access to external Docker clients, such as Docker for Mac running on
a dev's laptop.  The registry tool can quickly take care of installing the
registry certificate and also (optionally) configuring /etc/hosts to make the registry
address resolvable. For example, if there is registry called `test-docker-reg`
available at 192.168.1.103:

```
$ sudo ./reg-tool.sh install-cert \
         --cert-file ca.crt \
         --reg-name test-docker-reg:5000 \
         --add-host 192.168.1.103 test-docker-reg
Installing certificate
Assuming running Docker for Mac - adding certificate to internal VM

Exposing registry via /etc/hosts
497
442

Succesfully configured localhost
```

And now the following should work:

```
$ docker tag alpine:latest test-docker-reg:5000/test-image
$ docker push test-docker-reg:5000/test-image
The push refers to a repository [test-docker-reg:5000/test-image]
011b303988d2: Pushed
latest: digest: sha256:1354db23ff5478120c980eca1611a51c9f2b88b61f24283ee8200bf9a54f2e5c size: 528
```

This works on both Linux and Mac hosts. When using Docker for Mac, the
certificate will be added to the internal VM that Docker for Mac uses.
Unfortunately this means that you will need to run this command each time Docker
for Mac is restarted, as the internal VM gets reset.

Certificates can also be retrieved from URLs or a Kubernetes secret.

If the registry address is already resolvable, omit the `--add-host` flag to
prevent `/etc/hosts` being edited.

## Installing a Secure Reigstry on Kubernetes

Whilst there is an existing [cluster addon to start a
registry](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/registry),
it suffers from several flaws:

 - It does not use TLS. This means all transfers are unencrypted.
 - Each cluster node runs an instance of haproxy (the kube-registry-proxy image).
 - Another proxy has to be set-up to enable access from developer's machines

Using this tool will:

 - Install a registry on the current cluster with a self-signed certificate.
 - Configure all nodes to access the registry via TLS.
 - Use NodePorts to avoid the need to run haproxy.
 - Support easy installation of the certificate on local clients (e.g.
   developer's latops).

It will not currently configure a storage backend; please take a look at the
config files to see how to do this.

The script has been tested with
[minikube](https://github.com/kubernetes/minikube) and GCE clusters. 

WARNING: This will do funky stuff like edit /etc/hosts. It will warn before
doing this, but please be aware that it could break things. If you want to get a
secure registry running on existing cluster already handling load, I suggest you
look at what the scripts do and run the steps manually.

### Usage

The script will target whichever cluster `kubectl` currently points at.
Assuming your cluster is up-and-running, try:

```
$ ./reg-tool.sh install-k8s-reg
```

Once that completes, you should have running registry with certificates copied
to all nodes and networking configured. You can then configure the local Docker
daemon to access the registry with:

```
$ sudo ./reg-tool.sh install-cert --add-host
```

This command should work on any Linux or Docker for Mac host whose kubectl is
pointing at a cluster running a configured registry. We can then test with:


```
$ docker pull redis
...
$ docker tag redis kube-registry.kube-system.svc.cluster.local:31000/redis
$ docker push kube-registry.kube-system.svc.cluster.local:31000/redis
...
$ kubectl run r1 --image kube-registry.kube-system.svc.cluster.local:31000/redis
```

Please note that it sometimes takes a few minutes for DNS to update.

## Minikube

If you're using minikube, note that you can also use the Docker daemon in the VM
to access the registry. Rather than using the script to install a certificate
you can just do:

```
$ eval $(minkube docker-env)
```

## Further Development

Was this useful to you? Or would you like to see different features? 

Container Solutions are currently looking at developing tooling for working with
images and registries on clusters. Please get in touch if you'd like to hear
more or discuss ideas.

 - adrian.mouat@container-solutions.com
 - [@adrianmouat](https://twitter.com/adrianmouat)

