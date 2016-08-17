# secure-kube-reg
Scripts to get a secure kubernetes registry up and running

WARNING: This will do funky stuff like edit /etc/hosts. It's intended for
testing and development e.g. on a local minikube cluster. Please read and
understand the scripts before use. DO NOT RUN ON A PRODUCTION CLUSTER!

Note that the scripts will target whichever cluster `kubectl` currently points at.

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



