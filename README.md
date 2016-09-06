# secure-kube-reg
Scripts to get a secure Kubernetes registry up and running.

Whilst there is an existing module 

WARNING: This will do funky stuff like edit /etc/hosts. It will warn before
doing this, but please be aware that it could break things. If you want to get a
secure registry running on existing cluster already handling load, I suggest you
look at what the scripts do and run the steps manually.

Note that the scripts will target whichever cluster `kubectl` currently points
at.

## Usage

Assuming you have minikube or similar up and running, try:

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

e-mail: adrian.mouat@container-solutions.com
twitter: @adrianmouat

