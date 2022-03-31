#!/bin/bash

username=""
dockerpat=""
adspat=""
company=cabi
namespacedev=development
namespacestaging=staging
kubernetescontrolplane="10.10.4.20"

while getopts ":u:c:n:q:s:d:g:p:" opt; do
  case $opt in
    u) username="$OPTARG"
    ;;
    c) company="$OPTARG"
    ;;
    n) namespacedev="$OPTARG"
    ;;
    s) namespacestaging="$OPTARG"
    ;;
    d) dockerpat="$OPTARG"
    ;;
    g) adspat="$OPTARG"
    ;;
    p) kubernetescontrolplane="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

echo generating certificate

sudo openssl genrsa -out user-$username.key 2048
sudo openssl req -new -key user-$username.key -out user-$username.csr -subj "/CN=$username/O=$company"
sudo openssl x509 -req -in user-$username.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out user-$username.crt -days 500

echo removing temporary certificate

rm -f user-$username.csr

echo storing values in variables

cacrt=$(sudo cat /etc/kubernetes/pki/ca.crt | base64 | tr -d '\n')
crt=$(cat user-$username.crt | base64 | tr -d '\n')
key=$(sudo cat user-$username.key | base64 | tr -d '\n')

echo remove any existing user

rm -f user-$username.config

echo generate user

cat <<EOM >user-$username.config
apiVersion: v1
kind: Config
users:
- name: $username
  user:
    client-certificate-data: $crt
    client-key-data: $key
clusters:
- cluster:
    certificate-authority-data: $cacrt
    server: https://$kubernetescontrolplane:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    namespace: sandbox-$username
    user: $username
  name: $username-context@kubernetes
current-context: $username-context@kubernetes
EOM


if [ "$4" != "" ]; then
echo storing certificate to allow context use

kubectl config set-credentials $username --client-certificate=user-$username.crt  --client-key=user-$username.key
kubectl config set-context $username-context --cluster=kubernetes --namespace=$namespacedev --user=$username
else
echo discarding certificates

rm -f user-$username.crt
rm -f user-$username.key
fi

echo creating sandbox

kubectl create ns sandbox-$username

echo adding Docker Hub secret to allow repo access

kubectl delete secret dockerhub-cabi -n sandbox-$username

kubectl create secret docker-registry dockerhub-cabi --docker-username=cabicicd --docker-password=$dockerpat --docker-email= --namespace sandbox-$username

echo fetching config from Git

rm -R -f cabi-config
git clone https://CABIADS:$adspat@dev.azure.com/CABIADS/CabiSites/_git/Cabi.Configuration cabi-config

echo setting up config files using Helm chart

helm repo add cabi https://helm.cabi.org/
helm repo update
helm upgrade --namespace sandbox-$username --install -f cabi-config/common.yaml -f cabi-config/development.yaml -f cabi-config/sandbox.yaml --set cabiUrls.overrideNamespace=development cabi-configuration cabi/CabiConfiguration

echo generated roles

cat <<EOM >user-$username.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $namespacedev
  name: pod-reader
rules:
- apiGroups: ["extensions", "apps","networking.k8s.io", "extensions", "autoscaling", "cert-manager.io","mongodbcommunity.mongodb.com","atlas.mongodb.com"]
  resources: ["deployments","ingresses","daemonsets","replicasets","horizontalpodautoscalers","statefulsets","certificates","certificaterequests","ingress","mongodbcommunity","atlasclusters","atlasdatabaseusers","atlasprojects"]
  verbs: ["get", "watch", "list"]
- apiGroups: [""] # "" indicates the core API group
  resources: ["pods","pods/log","services","configmaps","replicationcontrollers","persistentvolumeclaims","endpoints","events"]
  verbs: ["get", "watch", "list", "exec","describe"]
- apiGroups: [""] # "" indicates the core API group
  resources: ["pods"]
  verbs: ["delete", "patch"]
- apiGroups: [""] # "" indicates the core API group
  resources: ["secrets"]
  verbs: ["list"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: ["batch"]
  resources:
  - jobs
  - cronjobs
  verbs: ["get","watch","list"]
---

apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $namespacestaging
  name: pod-basic-reader
rules:
- apiGroups: ["extensions", "apps","networking.k8s.io", "extensions", "autoscaling", "cert-manager.io","mongodbcommunity.mongodb.com","atlas.mongodb.com"]
  resources: ["deployments","ingresses","daemonsets","replicasets","horizontalpodautoscalers","statefulsets","certificates","certificaterequests","ingress","mongodbcommunity","atlasclusters","atlasdatabaseusers","atlasprojects"]
  verbs: ["get", "watch", "list"]
- apiGroups: [""] # "" indicates the core API group
  resources: ["pods","pods/log","services","configmaps","replicationcontrollers","persistentvolumeclaims","endpoints","events"]
  verbs: ["get", "watch", "list", "describe"]
- apiGroups: [""] # "" indicates the core API group
  resources: ["pods"]
  verbs: ["delete"]
- apiGroups: [""] # "" indicates the core API group
  resources: ["secrets"]
  verbs: ["list"]
- apiGroups: ["batch"]
  resources:
  - jobs
  - cronjobs
  verbs: ["get","watch","list"]
---

apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-$username
  namespace: $namespacedev
subjects:
- kind: User
  name: $username
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io

---

apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-basic-reader-$username
  namespace: $namespacestaging
subjects:
- kind: User
  name: $username
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-basic-reader
  apiGroup: rbac.authorization.k8s.io

---

apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: sandbox-$username
  name: sandbox-admin
rules:
- apiGroups: ["", "networking.k8s.io", "extensions", "apps", "autoscaling", "cert-manager.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["batch"]
  resources:
  - jobs
  - cronjobs
  verbs: ["*"]
---

apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: sandbox-owner
  namespace: sandbox-$username
subjects:
- kind: User
  name: $username
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: sandbox-admin
  apiGroup: rbac.authorization.k8s.io
EOM

echo apply roles

kubectl apply -f user-$username.yaml

echo removing creation yaml

rm user-$username.yaml

echo
echo Copy this file into a config file name $username.config and place in a folder on your machine called c:\k8s
echo

cat user-$username.config

echo
