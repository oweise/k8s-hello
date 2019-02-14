Kubernetes Dashboard 
====================

The files in this directory are used to deploy a [kubernetes dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/) 
to your cluster.

Instructions
------------


* Install the k8s dashboard
** More details here: https://github.com/kubernetes/dashboard/wiki/Installation

```
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml
```

* Install heapster (used by dashboard for displaying resource usage)
** More details here: https://github.com/kubernetes-retired/heapster
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml
```

* Install influxdb (used by heapster for storing metrics)
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml
```

* Create eks-admin Service Account and Cluster Role Binding
** Used to securely connect to the dashboard with admin-level permissions
```
cd ./dashboard
kubectl apply -f eks-admin-service-account.yaml
kubectl apply -f eks-admin-cluster-role-binding.yaml
```

* Ouput token for the eks-admin user, copying the token for the next step
```
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')
```

* Start the proxy for tunneling http request to dashboard.
```
kubectl proxy --port=9001
```

* Open the dashboard
on URL `http://localhost:9001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/`
** Select _Token_ and paste the _Token_ from above.

