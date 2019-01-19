#!/bin/bash


# This script was created on a mac book pro running high sierra.
# This requires brew to be installed or just make sure you have kubectl, helm, kops, wget, jq, and curl installed
# Please setup your awscli and export your keys before running script.
# Make sure you install curl, wget, and jq
# You will need to change a few things to get it running in your account like DNS zone and domain name.
# The ingress yaml file will also need to be changed to your host.domain along with a few other yaml files.
# This script does a DNS entry and creates an SSL/TLS cert with letsencrypt.
# The demo app is from azure sample apps and deployed with helm.
# Removed the aws command line option to add port 8089. cert-manager does not need it.
# you can delete the cluster with this command -  kops delete cluster code.ghettolabs.io --state s3://code.ghettolabs.io-state --yes




if ! [ -x "$(command -v kops)" ]; then
  echo 'Error: kops is not installed.' >&2
  echo 'Installing Kops'
  curl -Lo kops https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-darwin-amd64
  chmod +x ./kops
  sudo mv ./kops /usr/local/bin/
fi


if ! [ -x "$(command -v kubectl)" ]; then
   echo 'Error: kubectl is not installed.' >&2
   echo 'Installing kubectl'
   brew install kubernetes-cli
 fi

if ! [ -x "$(command -v helm)" ]; then
   echo 'Error: helm is not installed.' >&2
   echo 'Installing helm'
   brew install kubernetes-helm
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
sleep 1200 

# Setup helm and initialize tiller

kubectl create -f https://raw.githubusercontent.com/k8s-class/helm/master/helm-rbac.yaml
helm init --service-account tiller

sleep 300

# Setup nginx ingress controller and cert-manager

helm install --name my-ingress-controller stable/nginx-ingress --set controller.kind=DaemonSet --set controller.hostNetwork=true --set rbac.create=true

helm install \
    --name cert-manager \
    --namespace kube-system \
    stable/cert-manager

sleep 300

# Setup demo app

helm repo add azure-samples https://azure-samples.github.io/helm-charts/
helm install azure-samples/aks-helloworld

git clone https://github.com/k8s-class/demo.git
cd demo
kubectl apply -f .


sleep 600

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



