#!/bin/bash

if ! [ -x "$(command -v kops)" ]; then
  echo 'Error: kops is not installed.' >&2
  echo 'Installing Kops'
  curl -Lo kops https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
  chmod +x ./kops
  sudo mv ./kops /usr/local/bin/
fi


if ! [ -x "$(command -v kubectl)" ]; then
   echo 'Error: kubectl is not installed.' >&2
   echo 'Installing kubectl'
   curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
   chmod +x ./kubectl
   sudo mv ./kubectl /usr/local/bin/
 fi

if ! [ -x "$(command -v helm)" ]; then
   echo 'Error: helm is not installed.' >&2
   echo 'Installing helm'
   wget https://storage.googleapis.com/kubernetes-helm/helm-v2.9.1-linux-amd64.tar.gz
   tar -xzvf helm-v2.9.1-linux-amd64.tar.gz
   sudo mv linux-amd64/helm /usr/local/bin/helm
fi

# Must change: Your domain name that is hosted in AWS Route 53
export DOMAIN_NAME="ghettolabs.io"

# Friendly name to use as an alias for your cluster
export CLUSTER_ALIAS="code"

# Leave as-is: Full DNS name of you cluster
export CLUSTER_FULL_NAME="${CLUSTER_ALIAS}.${DOMAIN_NAME}"

# AWS availability zone where the cluster will be created
export CLUSTER_AWS_AZ="us-east-1a"


aws s3api create-bucket --bucket ${CLUSTER_FULL_NAME}-state

export KOPS_STATE_STORE="s3://${CLUSTER_FULL_NAME}-state"

kops create cluster \
    --name=${CLUSTER_FULL_NAME} \
    --zones=${CLUSTER_AWS_AZ} \
    --master-size="t2.medium" \
    --node-size="t2.medium" \
    --node-count="3" \
    --dns-zone=${DOMAIN_NAME} \
    --ssh-public-key="~/.ssh/id_rsa.pub" \
    --kubernetes-version="1.11.6"

kops update cluster ${CLUSTER_FULL_NAME} --yes


# Need to make sure the cluster is up before we start deploying anything
sleep 20m

# Setup helm and initialize tiller

kubectl create -f https://raw.githubusercontent.com/k8s-class/helm/master/helm-rbac.yaml
helm init --service-account tiller

sleep 15m

# Setup nginx ingress controller and cert-manager

helm install --name my-ingress-controller stable/nginx-ingress --set controller.kind=DaemonSet --set controller.hostNetwork=true --set rbac.create=true

helm install \
    --name cert-manager \
    --namespace kube-system \
    stable/cert-manager

sleep 10m

# Setup basic app - "This is my actual code"

git clone https://github.com/k8s-class/nginx-ingress.git
cd nginx-ingress
cd basicwebapp/templates
kubectl apply -f .

sleep 30m

ELB=$(kubectl get services --all-namespaces | grep LoadBalancer | awk '{print $5}')
export ELB
MYIP=$(ping -c1 $ELB | sed -nE 's/^PING[^(]+\(([^)]+)\).*/\1/p')
export MYIP
curl -k https://$ELB -H "Host: helloworld-v1.ghettolabs.io"


ENV=helloworld-v1

# Creates route 53 records based on env name

aws route53 change-resource-record-sets --hosted-zone-id Z1VROVT3ELLEHX \
--change-batch '{ "Comment": "Creating a record set",
"Changes": [ { "Action": "CREATE", "ResourceRecordSet": { "Name":
"'"$ENV"'.ghettolabs.io", "Type": "A", "TTL":
120, "ResourceRecords": [ { "Value": "'"$MYIP"'" } ] } } ] }'


sleep 15m

curl https://helloworld-v1.ghettolabs.io


