#########################################################
###  This Module will create the Internet Gateway(s)  ###
###            rquired for this lab                   ###  
#########################################################
#
# NOTE: one IGW per VPC is the AWS limit - this lab only has one VPC, so
# only one IGW is needed. Attached to aws_vpc.main-vpc from 02-vpc.tf.
#
#--------------------------------------------------------

# Create the Internet Gateway resource
resource "aws_internet_gateway" "main-igw" {
  vpc_id = aws_vpc.main-vpc.id

  tags = {
    Name       = "demo-igw-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================