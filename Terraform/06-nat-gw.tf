####################################################
###  This Module will create the NAT Gateway(s)  ###
###           rquired for this lab               ###  
####################################################
#
# NOTE: one NAT Gateway for the whole lab, in the public subnet, giving
# every node in the private subnet outbound internet access (package
# installs, pulling images, etc.) without exposing them directly.
#
#---------------------------------------------------


# Create the Public Subnet NAT GW
resource "aws_nat_gateway" "main-natgw" {
  depends_on    = [aws_internet_gateway.main-igw]
  allocation_id = aws_eip.nat-gw-eip.id
  subnet_id     = aws_subnet.pub-sub-01.id

  tags = {
    Name       = "demo-natgw-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================