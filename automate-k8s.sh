#!/bin/bash


# This script was created with ubuntu 18.04.
# Please setup your awscli and export your keys before running script.
# Make sure you install curl, wget, and jq
# You will need to change a few things to get it running in your account like DNS zone and domain name.
# The ingress yaml file will also need to be changed to your host.domain along with a few other yaml files.
# This script does a DNS entry and creates an SSL/TLS cert with letsencrypt.
# The demo app is from azure sample apps and deployed with helm.




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

sleep 5m

# Setup nginx ingress controller and cert-manager

helm install --name my-ingress-controller stable/nginx-ingress --set controller.kind=DaemonSet --set controller.hostNetwork=true --set rbac.create=true

helm install \
    --name cert-manager \
    --namespace kube-system \
    stable/cert-manager

sleep 5m

# Setup demo app

helm repo add azure-samples https://azure-samples.github.io/helm-charts/
helm install azure-samples/aks-helloworld

git clone https://github.com/k8s-class/demo.git
cd demo
kubectl apply -f .


sleep 10m

ELB=$(kubectl get services --all-namespaces | grep LoadBalancer | awk '{print $5}')
export ELB
MYIP=$(ping -c1 $ELB | sed -nE 's/^PING[^(]+\(([^)]+)\).*/\1/p')
export MYIP
curl -k https://$ELB -H "Host: demo.ghettolabs.io"


ENV=demo

# Creates route 53 records based on env name

aws route53 change-resource-record-sets --hosted-zone-id Z1VROVT3ELLEHX \
--change-batch '{ "Comment": "Creating a record set",
"Changes": [ { "Action": "CREATE", "ResourceRecordSet": { "Name":
"'"$ENV"'.ghettolabs.io", "Type": "A", "TTL":
120, "ResourceRecords": [ { "Value": "'"$MYIP"'" } ] } } ] }'


sleep 5m

# Open up port 8089 for Cert-Manager

export INSTANCE=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=nodes.code.ghettolabs.io" | grep InstanceId | awk '{print $2}' | cut -d'"' -f2 | awk '{print $1}' | head -1)

export SECURITYGROUP=$(aws ec2 describe-instance-attribute --instance-id $INSTANCE --attribute groupSet | jq .Groups | jq ".[] | .GroupId" | cut -d'"' -f2)

aws ec2 authorize-security-group-ingress --group-id $SECURITYGROUP --protocol tcp --port 8089 --cidr 0.0.0.0/0





