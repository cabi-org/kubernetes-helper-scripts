#!/bin/bash

username=""
company=cabi
namespaceexec=production
namespaceread=
kubernetescontrolplane=$(kubectl config view --minify -o jsonpath={.clusters[0].cluster.server})
keepusercerts=false

while getopts ":u:c:p:k:?:" opt; do
  case $opt in
    u) username="$OPTARG"
    ;;
    c) company="$OPTARG"
    ;;
    p) kubernetescontrolplane="$OPTARG"
    ;;
    k) keepusercerts=($OPTARG="true")
    ;;
    ?) 
    echo "Usage: helpers/admin-create.sh [OPTIONS]"
    echo
    echo "General Options"
    echo "  u = user name (in the format first-name) of account to create"
    echo "  c = name of company used in generated certificate (default: $company)"
    echo "  k = if true, user certificates are added to the local configuration to allow use on this machine (default: $keepusercerts)"
    echo "  p = Protocol, IP/name and port of Kubernetes control plane (default: $kubernetescontrolplane)"
    exit 0
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ "$username" == "" ]; then
echo ERROR: You must specifiy a user name in the format first-name
exit 1
fi

echo actual username to use will be $username-admin
username=$username-admin

echo generating certificate

sudo openssl genrsa -out admin-$username.key 2048
sudo openssl req -new -key admin-$username.key -out admin-$username.csr -subj "/CN=$username/O=$company"
sudo openssl x509 -req -in admin-$username.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out admin-$username.crt -days 500

echo removing temporary certificate

rm -f admin-$username.csr

echo storing values in variables

cacrt=$(sudo cat /etc/kubernetes/pki/ca.crt | base64 | tr -d '\n')
crt=$(cat admin-$username.crt | base64 | tr -d '\n')
key=$(sudo cat admin-$username.key | base64 | tr -d '\n')

echo remove any existing user

rm -f admin-$username.config

echo generate user

cat <<EOM >admin-$username.config
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
    server: $kubernetescontrolplane
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    namespace: default
    user: $username
  name: $username-context@kubernetes
current-context: $username-context@kubernetes
EOM


if [ keepusercerts == true ]; then
echo storing certificate to allow context use

kubectl config set-credentials $username --client-certificate=admin-$username.crt  --client-key=admin-$username.key

IFS=',' read -r -a array <<< "$namespaceexec"
for namespace in "${array[@]}"
do
kubectl config set-context $username-context --cluster=kubernetes --namespace=$namespace --user=$username
done

IFS=',' read -r -a array <<< "$namespaceread"
for namespace in "${array[@]}"
do
kubectl config set-context $username-context --cluster=kubernetes --namespace=$namespace --user=$username
done

else
echo discarding certificates

rm -f admin-$username.crt
rm -f admin-$username.key
fi

echo add role binding

cat <<EOM >admin-$username.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-$username
subjects:
- kind: User
  name: $username
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
EOM

echo apply roles for sandbox

kubectl apply -f admin-$username.yaml

echo removing creation yaml

rm admin-$username.yaml

echo
echo Copy this file into a config file name $username.config and place in a folder on your machine called c:\k8s
echo

cat admin-$username.config

echo
