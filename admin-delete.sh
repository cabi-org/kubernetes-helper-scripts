#!/bin/bash

kubectl config delete-context $1-context
kubectl config delete-user $1

kubectl delete clusterrolebinding -n kube-system admin-$1
