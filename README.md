### Set some Env Vars
```
# Must change: Your domain name that is hosted in AWS Route 53
export DOMAIN_NAME="aheadlabs.io"

# Friendly name to use as an alias for your cluster
export CLUSTER_ALIAS="First Name"

# Leave as-is: Full DNS name of you cluster
export CLUSTER_FULL_NAME="${CLUSTER_ALIAS}.${DOMAIN_NAME}"

# AWS availability zone where the cluster will be created
export CLUSTER_AWS_AZ="us-east-1a"

```
### Create an S3 Bucket
```
aws s3api create-bucket --bucket ${CLUSTER_FULL_NAME}-state
```

### Export your state store location for Kops

```
export KOPS_STATE_STORE="s3://${CLUSTER_FULL_NAME}-state"
```

### Create your Cluster

```
kops create cluster \
    --name=${CLUSTER_FULL_NAME} \
    --zones=${CLUSTER_AWS_AZ} \
    --master-size="t2.medium" \
    --node-size="t2.medium" \
    --node-count="3" \
    --dns-zone=${DOMAIN_NAME} \
    --ssh-public-key="~/.ssh/id_rsa.pub" \
    --kubernetes-version="1.11.2"
    
```

### Deploy the cluster

```
kops update cluster ${CLUSTER_FULL_NAME} --yes
```




