########################################################
###  This Module will create the Security Group(s),  ###
###          The Security Group Rule(s),             ###  
###       The Secuirty Groups Association(s)         ###
########################################################
#
# NOTE: every rule below is scoped by CIDR block or by security group
# reference (source_security_group_id), never by individual instance -
# any node placed in priv-sub-01 automatically inherits these rules
# through priv-sg-01.
#
#-------------------------------------------------------


# First create the Security Group(s)
#-----------------------------------

# Create Public Security Group
resource "aws_security_group" "pub-sg-01" {
  name        = "public-security-group-01"
  description = "Public Security Group allowing specific ports from the internet and denying the rest"
  vpc_id      = aws_vpc.main-vpc.id

  tags = {
    Name       = "public-security-group-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

# Create Private Security Group
resource "aws_security_group" "priv-sg-01" {
  name        = "private-security-group-01"
  description = "Private Security Group denying all ports from the internet"
  vpc_id      = aws_vpc.main-vpc.id

  tags = {
    Name       = "private-security-group-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================

# Second create the Security Group Rule(s) & Association(s)
#----------------------------------------------------------

# Allows anyone on the internet to SSH to whatever sits in pub-sg-01 -
# in practice, only the bastion (the sole public-subnet instance).
# Create Public Security Group Ingress SSH Rules - Bastion access only
resource "aws_security_group_rule" "pub-sg-ingress-ssh-rules-01" {
  depends_on        = [aws_security_group.pub-sg-01]
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.pub-sg-01.id
}

# Opens port 80 to the internet - reaches the NLB's HTTP listener.
# Create Public Security Group Ingress HTTP Rules - NLB listener
resource "aws_security_group_rule" "pub-sg-ingress-http-rules-01" {
  depends_on        = [aws_security_group.pub-sg-01]
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.pub-sg-01.id
}

# Opens port 443 to the internet - reaches the NLB's HTTPS listener.
# Create Public Security Group Ingress HTTPS Rules - NLB listener
resource "aws_security_group_rule" "pub-sg-ingress-htts-rules-01" {
  depends_on        = [aws_security_group.pub-sg-01]
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.pub-sg-01.id
}

# Lets anything else inside the VPC (e.g. the Kube nodes replying to the
# bastion or the NLB) reach the public subnet on any port.
# Create Public Security Group Ingress internal Rules
resource "aws_security_group_rule" "pub-sg-ingress-internal-rules-01" {
  depends_on        = [aws_security_group.pub-sg-01]
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [aws_vpc.main-vpc.cidr_block]
  security_group_id = aws_security_group.pub-sg-01.id
}

# Unrestricted outbound - the bastion and NLB can reach anything.
# Create Public Security Group Egress Rules
resource "aws_security_group_rule" "pub-sg-egress-rules-01" {
  depends_on        = [aws_security_group.pub-sg-01]
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.pub-sg-01.id
}

# Lets every Kube node talk to every other Kube node on any port -
# needed for cluster-internal traffic (etcd, kubelet, pod networking)
# regardless of how many masters or workers exist.
# Create Private Security Group Ingress Rules - Allow traffic from VPC subnet
resource "aws_security_group_rule" "priv-sg-ingress-rules-01" {
  depends_on        = [aws_security_group.priv-sg-01]
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [aws_vpc.main-vpc.cidr_block]
  security_group_id = aws_security_group.priv-sg-01.id
}

# Create Private Security Group Ingress Rules - Allow traffic from instances in public security group
# Reason behind this is twofold: the bastion (public SG) needs SSH into the Kube nodes,
# and the NLB (public SG) needs to forward HTTP/HTTPS to whichever node the ingress controller lands on
resource "aws_security_group_rule" "priv-sg-ingress-rules-02" {
  depends_on               = [aws_security_group.priv-sg-01]
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.pub-sg-01.id
  security_group_id        = aws_security_group.priv-sg-01.id
}

# Unrestricted outbound - Kube nodes reach the internet via the NAT
# Gateway (for package installs, image pulls, etc.).
# Create Private Security Group Egress Rules
resource "aws_security_group_rule" "priv-sg-egress-rules-01" {
  depends_on        = [aws_security_group.priv-sg-01]
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.priv-sg-01.id
}

#========================================