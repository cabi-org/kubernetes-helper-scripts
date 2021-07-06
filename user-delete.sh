#!/bin/bash

if [ "$2" != "" ]; then
namespace=$2
else
namespace=development
fi

kubectl config delete-context $1-context
kubectl config delete-user $1

kubectl delete rolebinding -n $namespace pod-reader-$1

kubectl delete ns sandbox-$1
