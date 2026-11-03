################################################################
###  This Module will create the VPC(s) rquired for this lab ###  
################################################################
#
# NOTE: cidr_block comes from var.vpc-cidr (see variables.tf, Second
# Networking variables). It defaults to 10.10.0.0/16 and is validated
# there, not here.
#
#---------------------------------------------------------------

# Create VPC(s)
#--------------

# Create the main VPC resource
resource "aws_vpc" "main-vpc" {
  cidr_block            = var.vpc-cidr
  enable_dns_hostnames  = true

  tags = {
    Name       = "demo-vpc-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}