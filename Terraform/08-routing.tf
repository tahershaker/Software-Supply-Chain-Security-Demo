#######################################################
###  This Module will create the Routing Table(s),  ###
###      The Route(s), & The Association(s)         ###  
#######################################################
#
# NOTE: routes and associations are per-subnet, not per-instance - this
# defines how traffic leaves each subnet, not how it reaches any one
# node. The public route table sends outbound traffic straight to the
# Internet Gateway; the private route table sends it through the NAT
# Gateway instead, so nodes get outbound access without a public IP.
#
#------------------------------------------------------

# First create the Routing Table(s) & Route(s)
#---------------------------------------------

# Public subnet's default route goes straight to the Internet Gateway.
# Create Public Routing Table
resource "aws_route_table" "pub-rt-01" {
  depends_on = [aws_internet_gateway.main-igw]
  vpc_id     = aws_vpc.main-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main-igw.id
  }

  tags = {
    Name       = "demo-pub-rt-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

# Private subnet's default route goes through the NAT Gateway, so nodes
# get outbound internet access without a public IP of their own.
# Create Private Routing Table
resource "aws_route_table" "priv-rt-01" {
  depends_on = [aws_nat_gateway.main-natgw]
  vpc_id     = aws_vpc.main-vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main-natgw.id
  }

  tags = {
    Name       = "demo-priv-rt-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================

# Second create the Routing Table(s) Association(s)
#--------------------------------------------------

# Create Public Routing Table Association with public subnet
resource "aws_route_table_association" "pub-rt-association-01" {
  subnet_id      = aws_subnet.pub-sub-01.id
  route_table_id = aws_route_table.pub-rt-01.id
}

# Create Private Routing Table Association with private subnet
resource "aws_route_table_association" "priv-rt-association-01" {
  subnet_id      = aws_subnet.priv-sub-01.id
  route_table_id = aws_route_table.priv-rt-01.id
}

#========================================