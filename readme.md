# Run Amazon CLI
docker run -it --rm -v ${PWD}:/work -w /work --entrypoint /bin/sh amazon/aws-cli:2.0.43

# some handy tools
yum install -y jq gzip nano tar git unzip wget

Login to Amazon
# Access your "My Security Credentials" section in your profile. 
# Create an access key

aws configure

Default region name: ap-southeast-2

Default output format: json


# Get Terraform

curl -o /tmp/terraform.zip -LO https://releases.hashicorp.com/terraform/0.14.3/terraform_0.14.3_linux_amd64.zip

unzip /tmp/terraform.zip

chmod +x terraform && mv terraform /usr/local/bin/


terraform init

terraform plan

terraform apply


# grab EKS config

aws eks update-kubeconfig --name getting-started-eks --region ap-southeast-1

# Get kubectl

curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl

chmod +x ./kubectl

mv ./kubectl /usr/local/bin/kubectl

kubectl get nodes

kubectl get deploy

kubectl get pods

kubectl get svc

Clean up

terraform destroy


# After we have our cluster, we'd set up an EFS storage driver for jenkins to have persistent data if this weren't a home asignment but a proper infrastructure

# deploy EFS storage driver

kubectl apply -k "github.com/kubernetes-sigs/
aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"

# get VPC ID

aws eks describe-cluster --name getting-started-eks --query "cluster.resourcesVpcConfig.vpcId" --output text

# Get CIDR range

aws ec2 describe-vpcs --vpc-ids vpc-id --query "Vpcs[].CidrBlock" --output text


# security for our instances to access file storage

aws ec2 create-security-group --description efs-test-sg --group-name efs-sg --vpc-id VPC_ID

aws ec2 authorize-security-group-ingress --group-id sg-xxx  --protocol tcp --port 2049 --cidr VPC_CIDR


# create storage

aws efs create-file-system --creation-token eks-efs


# create mount point 

aws efs create-mount-target --file-system-id FileSystemId --subnet-id SubnetID --security-group GroupID


# grab our volume handle to update our PV YAML

aws efs describe-file-systems --query "FileSystems[*].FileSystemId" --output text

# We'd also set up a namespace though for the assignment I deployed in default ns

kubectl create ns jenkins

# Now we'll set up the storage for jenkins with the yaml files included in this project

kubectl get storageclass

# create volume
kubectl apply -f ./jenkins/amazon-eks/jenkins.pv.yaml 

kubectl get pv


# create volume claim

kubectl apply -n jenkins -f ./jenkins/jenkins.pvc.yaml

kubectl -n jenkins get pvc

# Now deploy jenkins along with setting up rbac access control

kubectl apply -n jenkins -f ./jenkins/jenkins.rbac.yaml 

kubectl apply -n jenkins -f ./jenkins/jenkins.deployment.yaml

kubectl -n jenkins get pods

# Now we want to SSH to the node to get the docker user info so we can set up k8s as a cloud provider, though I did not do this on the home assignment due to time constraints

eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa
ssh -i ~/.ssh/id_rsa PUBLIC-DNS-NAME
id -u docker
cat /etc/group
# Get user ID for docker
# Get group ID for docker

# We'll use the Dockerfile included so every time jenkins initiates a build he can spin up a jenkins agent
# It also installs the docker CLI aswell as docker compose so we can also run docker build, run, command, push inside the jenkins slave and interact with the host
# Also allows caching docker images so the builds will run faster

docker build . -t jenkins-slave

# What we've so far is:
# Create an EKS cluster
# Created storage with EFS
# Deployed persistent volumes and hooked them up to the EFS storage
# Deployed jenkins server and wired it up to the storage
# Now if you got up to here you want to eventually reach a point where you spin up pods as agents of jenkins to run builds that are initiated
# Configure k8s as cloud on jenkins (after downloading the k8s plugin on jenkins) to allow that to happen, I did not do this here
