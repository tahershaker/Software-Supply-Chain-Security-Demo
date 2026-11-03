#######################################################
###  This Module will create the Load Balancer(s),  ###
###   its Target Group(s), and Listener(s)           ###  
#######################################################
#
# NOTE: this file assumes 10-compute.tf defines aws_instance.kube-master
# (count = var.kube-master-count) and aws_instance.kube-worker
# (count = var.kube-worker-count) as collections, not individually named
# resources. The target group attachments below loop over those counts,
# so any number of masters or workers gets registered automatically -
# no manual attachment block per node.
#
# NOTE: the last section creates an internal Network Load Balancer for the
# Kubernetes API (port 6443) and for RKE2 node registration (port 9345).
# It exists only when kube-master-count is 3. With 1 master there is
# nothing to balance, so no API load balancer is created. Its fixed
# address is .10 of the private subnet.
#
#------------------------------------------------------

# First create Load balancers

# Create Network Load Balancer and assign the EIP to it
resource "aws_lb" "nlb-01" {
  name                             = "demo-nlb-01"
  load_balancer_type               = "network"
  internal                         = false
  enable_cross_zone_load_balancing = true
  security_groups                  = [aws_security_group.pub-sg-01.id]

  subnet_mapping {
    subnet_id     = aws_subnet.pub-sub-01.id
    allocation_id = aws_eip.lb-eip.id
  }

  tags = {
    Name       = "demo-nlb-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================================================

# Second create Target Groups

# Create an http LB Target Group - forwards to the ingress controller on the Kube nodes
resource "aws_lb_target_group" "http-tg-01" {
  depends_on = [aws_lb.nlb-01]
  name       = "demo-http-tg-01"
  port       = 80
  protocol   = "TCP"
  vpc_id     = aws_vpc.main-vpc.id

  tags = {
    Name       = "demo-http-tg-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

# Create an https LB Target Group - forwards to the ingress controller on the Kube nodes
resource "aws_lb_target_group" "https-tg-01" {
  depends_on = [aws_lb.nlb-01]
  name       = "demo-https-tg-01"
  port       = 443
  protocol   = "TCP"
  vpc_id     = aws_vpc.main-vpc.id

  tags = {
    Name       = "demo-https-tg-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================================================

# Third create Target Group Attachments
# Every master AND every worker is registered on both target groups,
# since the ingress controller can land on any node in this demo
# cluster. count loops over however many nodes actually exist -
# kube-master-count masters, kube-worker-count workers.

# Create http Target Group Attachments - masters
resource "aws_lb_target_group_attachment" "http-tg-att-master" {
  count            = var.kube-master-count
  depends_on       = [aws_lb_target_group.http-tg-01]
  target_group_arn = aws_lb_target_group.http-tg-01.arn
  target_id        = aws_instance.kube-master[count.index].id
  port             = 80
}

# Create http Target Group Attachments - workers
resource "aws_lb_target_group_attachment" "http-tg-att-worker" {
  count            = var.kube-worker-count
  depends_on       = [aws_lb_target_group.http-tg-01]
  target_group_arn = aws_lb_target_group.http-tg-01.arn
  target_id        = aws_instance.kube-worker[count.index].id
  port             = 80
}

# Create https Target Group Attachments - masters
resource "aws_lb_target_group_attachment" "https-tg-att-master" {
  count            = var.kube-master-count
  depends_on       = [aws_lb_target_group.https-tg-01]
  target_group_arn = aws_lb_target_group.https-tg-01.arn
  target_id        = aws_instance.kube-master[count.index].id
  port             = 443
}

# Create https Target Group Attachments - workers
resource "aws_lb_target_group_attachment" "https-tg-att-worker" {
  count            = var.kube-worker-count
  depends_on       = [aws_lb_target_group.https-tg-01]
  target_group_arn = aws_lb_target_group.https-tg-01.arn
  target_id        = aws_instance.kube-worker[count.index].id
  port             = 443
}

#========================================================================

# Forth create Load Balancer Listeners

# Create http Listener
resource "aws_lb_listener" "http-listener-01" {
  depends_on        = [aws_lb.nlb-01, aws_lb_target_group.http-tg-01]
  load_balancer_arn = aws_lb.nlb-01.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http-tg-01.arn
  }
}

# Create https Listener
resource "aws_lb_listener" "https-listener-01" {
  depends_on        = [aws_lb.nlb-01, aws_lb_target_group.https-tg-01]
  load_balancer_arn = aws_lb.nlb-01.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https-tg-01.arn
  }
}

#========================================================================

# Fifth create the Kubernetes API Load Balancer (3-master clusters only)
#------------------------------------------------------------------------
# With 3 masters, every node reaches the Kubernetes API through one
# internal address - this NLB. With 1 master there is no API load
# balancer, since nodes use the master's private IP directly.
#
# The NLB listens on two ports:
#   - 6443: the Kubernetes API (kubeadm and RKE2)
#   - 9345: the RKE2 supervisor port, used by nodes joining an RKE2 cluster.
#           With kubeadm nothing listens on 9345, so its targets show as
#           unhealthy. That is harmless.

locals {
  create-api-nlb = var.kube-master-count == 3
}

# Create the internal API NLB with a fixed private IP (.10 of the private
# subnet - just below the master range, which starts at .11)
resource "aws_lb" "nlb-api-01" {
  count              = local.create-api-nlb ? 1 : 0
  name               = "demo-nlb-api-01"
  load_balancer_type = "network"
  internal           = true

  subnet_mapping {
    subnet_id            = aws_subnet.priv-sub-01.id
    private_ipv4_address = cidrhost(var.priv-sub-01-cidr, 10)
  }

  tags = {
    Name       = "demo-nlb-api-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================================================

# Create the Target Groups
# Client IP preservation is off on both, so a master can reach the NLB
# even when the NLB sends the connection back to that same master.

# Create the API Target Group - forwards to the Kubernetes API on the masters
resource "aws_lb_target_group" "api-tg-01" {
  count              = local.create-api-nlb ? 1 : 0
  depends_on         = [aws_lb.nlb-api-01]
  name               = "demo-api-tg-01"
  port               = 6443
  protocol           = "TCP"
  vpc_id             = aws_vpc.main-vpc.id
  target_type        = "instance"
  preserve_client_ip = "false"

  health_check {
    protocol            = "TCP"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name       = "demo-api-tg-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

# Create the RKE2 Registration Target Group - forwards to the RKE2
# supervisor port on the masters
resource "aws_lb_target_group" "rke2-tg-01" {
  count              = local.create-api-nlb ? 1 : 0
  depends_on         = [aws_lb.nlb-api-01]
  name               = "demo-rke2-tg-01"
  port               = 9345
  protocol           = "TCP"
  vpc_id             = aws_vpc.main-vpc.id
  target_type        = "instance"
  preserve_client_ip = "false"

  health_check {
    protocol            = "TCP"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name       = "demo-rke2-tg-01"
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

#========================================================================

# Register every master on both Target Groups

# Register every master on the API Target Group
resource "aws_lb_target_group_attachment" "api-tg-att-master" {
  count            = local.create-api-nlb ? var.kube-master-count : 0
  depends_on       = [aws_lb_target_group.api-tg-01]
  target_group_arn = aws_lb_target_group.api-tg-01[0].arn
  target_id        = aws_instance.kube-master[count.index].id
  port             = 6443
}

# Register every master on the RKE2 Registration Target Group
resource "aws_lb_target_group_attachment" "rke2-tg-att-master" {
  count            = local.create-api-nlb ? var.kube-master-count : 0
  depends_on       = [aws_lb_target_group.rke2-tg-01]
  target_group_arn = aws_lb_target_group.rke2-tg-01[0].arn
  target_id        = aws_instance.kube-master[count.index].id
  port             = 9345
}

#========================================================================

# Create the Listeners

# Create the API Listener
resource "aws_lb_listener" "api-listener-01" {
  count             = local.create-api-nlb ? 1 : 0
  depends_on        = [aws_lb.nlb-api-01, aws_lb_target_group.api-tg-01]
  load_balancer_arn = aws_lb.nlb-api-01[0].arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api-tg-01[0].arn
  }
}

# Create the RKE2 Registration Listener
resource "aws_lb_listener" "rke2-listener-01" {
  count             = local.create-api-nlb ? 1 : 0
  depends_on        = [aws_lb.nlb-api-01, aws_lb_target_group.rke2-tg-01]
  load_balancer_arn = aws_lb.nlb-api-01[0].arn
  port              = "9345"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rke2-tg-01[0].arn
  }
}

#========================================================================