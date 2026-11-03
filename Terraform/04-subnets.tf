###################################################
###  This Module will create the VPC Subnet(s)  ###
###           rquired for this lab              ###  
###################################################
#
# NOTE: both subnets sit in a single AZ ("${var.aws-region}a") - this is a
# demo, not a highly-available design, so no multi-AZ spread is used.
#
#--------------------------------------------------


# First create the public VPC subnet
#------------------------------------
#
# NOTE: cidr_block comes from var.pub-sub-01-cidr, defaults to
# 10.10.10.0/24 (see variables.tf, Second Networking variables).
#
# Hosts: the bastion host (fixed at .11) and the network load balancer.
# map_public_ip_on_launch = true because anything in this subnet is meant
# to be internet-reachable.

# Create the public subnet resource
resource "aws_subnet" "pub-sub-01" {
  vpc_id                  = aws_vpc.main-vpc.id
  cidr_block              = var.pub-sub-01-cidr
  availability_zone       = "${var.aws-region}a"
  map_public_ip_on_launch = true

  tags = {
    Name       = "demo-public-subnet-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================

# Second create the private VPC subnet
#--------------------------------------
#
# NOTE: cidr_block comes from var.priv-sub-01-cidr, defaults to
# 10.10.20.0/24 (see variables.tf, Second Networking variables).
#
# Hosts: the Kube master node(s) (fixed at .11-.19) and worker nodes
# (fixed at .21-.39). No map_public_ip_on_launch - these nodes are only
# reachable via the bastion (SSH) or the load balancer (HTTP/HTTPS), not
# directly from the internet.

# Create the private subnet resource
resource "aws_subnet" "priv-sub-01" {
  vpc_id            = aws_vpc.main-vpc.id
  cidr_block        = var.priv-sub-01-cidr
  availability_zone = "${var.aws-region}a"

  tags = {
    Name       = "demo-private-subnet-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================