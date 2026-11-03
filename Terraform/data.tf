#######################################################
###  This file will include the aws data provider   ###  
###      to be used to locate the required info     ### 
#######################################################
#
# NOTE: this is a single AMI lookup, used by the bastion and every master
# and worker node (10-compute.tf).
#
# NOTE: os-ami-owner, os-ami-name, os-ami-virtualization-type,
# os-ami-architecture, and os-ami-root-device-type together decide which
# AMI this resolves to - see the AMI note in variables.tf, and the
# README, before changing any of them.
#
#========================================================

# Get the OS AMI to use for the bastion and the Kube nodes
# var.os-ami-name controls the version - update it in variables.tf when you want to move
# to a different release (e.g. jammy 22.04 vs noble 24.04)
data "aws_ami" "ami-os" {
  most_recent = true
  owners      = [var.os-ami-owner]

  filter {
    name   = "name"
    values = [var.os-ami-name]
  }

  filter {
    name   = "virtualization-type"
    values = [var.os-ami-virtualization-type]
  }

  filter {
    name   = "architecture"
    values = [var.os-ami-architecture]
  }

  filter {
    name   = "root-device-type"
    values = [var.os-ami-root-device-type]
  }
}