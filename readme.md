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
