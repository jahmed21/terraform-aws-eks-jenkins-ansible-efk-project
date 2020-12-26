terraform {
  required_version = ">= 0.12.0"
}

provider "aws" {
  version = ">= 2.28.1"
  region  = var.region
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

data "aws_availability_zones" "available" {
}

resource "aws_security_group" "worker_group_mgmt_one" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.6.0"

  name                 = "test-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  # Define private and public subnets to allow flexibility of nodes and play with nodes that are exposed publicly and ones that are private
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  # Enable NAT gateway and DNS capability to allow autoscaling worker nodes
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

module "eks" {
  source       = "terraform-aws-modules/eks/aws"
  cluster_name    = var.cluster_name
  cluster_version = "1.18"
  # Hook up the private subnets so autoscaling node groups will run privately (my autoscaling node groups will have private IPs rather than be directly accesible from the internet)
  subnets         = module.vpc.private_subnets
  version = "13.2.1"
  cluster_create_timeout = "1h"
  # Allow private endpoints to connect to k8s and join the cluster automatically
  cluster_endpoint_private_access = true 

  # Tell the EKS module to use the vpc ID of the vpc I have defined previously
  vpc_id = module.vpc.vpc_id

  # Define the autoscaling groups
  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t3.medium"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 1
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    },
  ]

  worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
  # the module creates and AWS auth config map, so I can hook it up with additional things like rbac roles
  # and such to allow other users to access the clusters
  map_roles                            = var.map_roles
  map_users                            = var.map_users
  map_accounts                         = var.map_accounts
}

# Use the k8s provider to allow authentication to the newly created cluster
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.11"
}

resource "kubernetes_deployment" "jenkins" {
  metadata {
    name = "terraform-jenkins"
    labels = {
      app = "jenkins"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "jenkins"
      }
    }

    template {
      metadata {
        labels = {
          app = "jenkins"
        }
      }

      spec {
        container {
          image = "jenkins/jenkins:lts"
          name  = "jenkins"

          port {
            container_port = 8080
            name = "http-port"
          }

          port {
            container_port = 50000
            name = "jnlp-port"
          }
      }
    }
  }
}
}
# To expose the above deployment I deploy a k8s service
resource "kubernetes_service" "K8SLB" {
  metadata {
    name = "terraform-jenkinslb"
  }
  spec {
    selector = {
      app = "jenkins"
    }
    port {
      port        = 80
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}

# To expose allow use of k8s as cloud manager of jenkins and deployment of slave nodes to do the work, though unused at the moment
resource "kubernetes_service" "K8SJNLP" {
  metadata {
    name = "terraform-jenkins"
  }
  spec {
    selector = {
      app = "jenkins"
    }
    port {
      port        = 50000
      target_port = 50000
    }

    type = "ClusterIP"
  }
}

# In addition to deploying the cluster with autoscaling funcitonaclity from the get-go with autoscaling groups, using amazon load balancer ingress controller module
# for terraform to solve D question of high traffic that the cluster can't scale fast enough too, we are setting the cluster with a load balancer already in place
# Why is this important? because the K8SLB service I created already serves as a load balancer for one service at a time, so if I have multiple services that
# need to be exposed, I would need the same amount of load balancers. This is where deploying ingress comes in handy, specifically the ingress controller which
# this module deploys, the actual part that controls the load balancers, so they know how to serve the requests and forward the data to the Pods (like a reverse proxy).
# The Ingress routes the traffic based on paths, domains, headers, etc., which consolidates multiple endpoints in a single resource that runs inside Kubernetes. 
# With this, I can serve multiple services at the same time from one exposed load balancer.
# I am specifically using the module that integrates ingress controller with ALB as we are working in AWS

module "alb_ingress_controller" {
  source  = "iplabs/alb-ingress-controller/kubernetes"
  version = "3.4.0"

  /* providers = {
    kubernetes = "kubernetes.eks"
  } */

  k8s_cluster_type = "eks"
  k8s_namespace    = "kube-system"

  aws_region_name  = var.region
  k8s_cluster_name = var.cluster_name
}