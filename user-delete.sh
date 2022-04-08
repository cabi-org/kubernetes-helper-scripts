#!/bin/bash

kubectl delete rolebinding -n development pod-reader-$1
kubectl delete rolebinding -n staging pod-basic-reader-$1
kubectl delete rolebinding -n production pod-basic-reader-$1

kubectl delete clusterrolebinding -n kube-system admin-$1
kubectl delete clusterrolebinding -n kube-system admin-$1-admin

kubectl config delete-context $1-admin-context
kubectl config delete-context $1-context
kubectl config delete-user $1
kubectl config delete-user $1-admin

kubectl delete ns sandbox-$1
