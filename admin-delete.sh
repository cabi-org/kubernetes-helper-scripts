#!/bin/bash

kubectl config delete-context $1-admin-context
kubectl config delete-user $1-admin

kubectl delete clusterrolebinding -n kube-system admin-$1
kubectl delete clusterrolebinding -n kube-system admin-$1-admin
