# secure-kube-reg
Script to get a secure Kubernetes registry up and running with a
self-signed-cert.

Whilst there is an existing [cluster addon to start a registry](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/registry), it suffers from several flaws:

 - Most importantly, it does not use TLS. This means all transfers are
   unencrypted.
 - Each node has to run an instance of haproxy (the kube-registry-proxy image).
 - Setting up localhost access requires setting up kubectl to do port
   forwarding.

Using this script will:

 - Install a registry on the current cluster with a self-signed certificate.
 - Configure all nodes to access the registry via TLS.
 - Configure the local machine to access the registry via TLS.
 - Use NodePorts to avoid the need to run haproxy.

It will not currently configure a storage backend; please take a look at the
config files to see how to do this.

The script has been tested with [minikube](https://github.com/kubernetes/minikube) and GCE clusters.

WARNING: This will do funky stuff like edit /etc/hosts. It will warn before
doing this, but please be aware that it could break things. If you want to get a
secure registry running on existing cluster already handling load, I suggest you
look at what the scripts do and run the steps manually.


## Usage

The scripts will target whichever cluster `kubectl` currently points at.
Assuming your cluster is up-and-running, try:

```
$ sudo ./start-registry.sh
```

Once that completes, we can test it:

```
$ docker pull redis
...
$ docker tag redis kube-registry.kube-system.svc.cluster.local:31000/redis
$ docker push kube-registry.kube-system.svc.cluster.local:31000/redis
...
$ kubectl run r1 --image kube-registry.kube-system.svc.cluster.local:31000/redis
```

If you have already installed a registry using the script and want to set up
access on a new machine, just run:

```
$ sudo ./start-registry.sh -l
```

## Further Development

Was this useful to you? Or would you like to see different features? 

Container Solutions are currently looking at developing tooling for working with
images and registries on clusters. Please get in touch if you'd like to hear
more or discuss ideas.

 - adrian.mouat@container-solutions.com
 - [@adrianmouat](https://twitter.com/adrianmouat)

