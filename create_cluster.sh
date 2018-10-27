#!/bin/bash

kops create cluster \
                --name=${CLUSTER_FULL_NAME} \
                --zones=${CLUSTER_AWS_AZ} \
                --master-size="t2.micro" \
                --node-size="t2.micro" \
                --node-count="3" \
                --master-count="1" \
                --dns-zone=${DOMAIN_NAME} \
                --ssh-public-key="~/.ssh/id_rsa.pub" \
                --kubernetes-version="1.10.5" \
                --networking=calico \
                --authorization=RBAC \
                --state s3://prod.aheadlabs.io-state --yes
