#######################################################
###   This Module will create the EC2 Instance(s),  ###
###             Required for this lab               ###  
#######################################################
#
# NOTE: this file provisions the raw EC2 instances only - the bastion,
# the Kube master node(s), and the Kube worker node(s). Installing an
# operating system's specific configuration or Kubernetes itself is
# handled outside Terraform, in a separate step.
#
# NOTE: the number of master and worker nodes is user-configurable, not
# fixed. var.kube-master-count and var.kube-worker-count (variables.tf)
# each carry a default, so this works with no input at all, but either
# can be overridden - the actual instance count follows whatever value
# they resolve to.
#
# The count = ... argument on each resource is what turns a single
# resource block into a loop: Terraform creates that many copies of the
# block, numbered 0 through count - 1, and count.index is which copy is
# currently being created.
#
# Each node's private_ip is calculated, not typed in - cidrhost() takes
# the private subnet's CIDR and a host number, and returns the actual IP
# for that offset. The host number is var.kube-master-ip-start (or
# kube-worker-ip-start) plus count.index, so node 0 gets the start
# address, node 1 gets the next one, and so on - every node's IP is
# derived from its position in the loop, not set individually.
#
#------------------------------------------------------

# First create the SSH Key Pair localy and add it to AWS, and the RKE2 join token
#---------------------------------------------------------------------------------

# Create a random suffix so the key name is unique per deployment
resource "random_string" "ssh-key-random" {
  length  = 6
  special = false
  upper   = false
}

# Create an RSA Key Pair of size 4096 bits
resource "tls_private_key" "ssh-key-pair-local-01" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create the SSH Key on AWS
resource "aws_key_pair" "demo-ssh-key-pair-01" {
  depends_on = [tls_private_key.ssh-key-pair-local-01]
  key_name   = "${random_string.ssh-key-random.result}-demo-key"
  public_key = tls_private_key.ssh-key-pair-local-01.public_key_openssh
}

# Create a local file with the content of the SSH Key
resource "local_file" "demo-ssh-key-pair" {
  depends_on      = [tls_private_key.ssh-key-pair-local-01]
  content         = tls_private_key.ssh-key-pair-local-01.private_key_pem
  filename        = "${random_string.ssh-key-random.result}-${var.ssh-file-name}"
  file_permission = "0400"
}

# Create the shared RKE2 join token (only when var.install-rke2 is true).
# Every RKE2 node uses the same token to join the cluster, so Terraform
# generates it once here and passes it to the nodes in their user_data.
resource "random_password" "rke2-token" {
  count   = var.install-rke2 ? 1 : 0
  length  = 48
  special = false
}

#========================================

# Second create the locals used by the EC2 Instance(s)
#------------------------------------------------------

# Names, IPs and the RKE2 join settings are calculated once here and shared
# by every instance below. The names are used for both the Name tag and the
# hostname. The IPs use the same cidrhost() calculation as the instances.
# Every node gets the same /etc/hosts block, so each node can reach the
# others by name. Hostname settings follow the AWS static hostname guide:
# https://repost.aws/knowledge-center/linux-static-hostname
#
# The RKE2 locals decide where nodes join the cluster: the API NLB with 3
# masters, otherwise master 01. Master 01 starts the cluster, so it gets no
# server line.

locals {
  bastion-name = "demo-bastion-01"
  master-names = [for i in range(var.kube-master-count) : "demo-kube-master-${format("%02d", i + 1)}"]
  worker-names = [for i in range(var.kube-worker-count) : "demo-kube-worker-${format("%02d", i + 1)}"]

  bastion-ip = cidrhost(var.pub-sub-01-cidr, var.bastion-ip-host-num)
  master-ips = [for i in range(var.kube-master-count) : cidrhost(var.priv-sub-01-cidr, var.kube-master-ip-start + i)]
  worker-ips = [for i in range(var.kube-worker-count) : cidrhost(var.priv-sub-01-cidr, var.kube-worker-ip-start + i)]

  # The /etc/hosts entries added on every node
  hosts-block = join("\n", concat(
    ["# Terraform-managed node entries"],
    ["${local.bastion-ip} ${local.bastion-name}"],
    [for i, name in local.master-names : "${local.master-ips[i]} ${name}"],
    [for i, name in local.worker-names : "${local.worker-ips[i]} ${name}"]
  ))

  # RKE2: the address nodes use to join the cluster. With 3 masters it is the
  # API NLB (.10 of the private subnet), otherwise it is master 01.
  rke2-join-ip = local.create-api-nlb ? cidrhost(var.priv-sub-01-cidr, 10) : local.master-ips[0]

  # RKE2: the server line for each master. Master 01 starts the cluster, so
  # its line is empty. Masters 2 and 3 join through the address above.
  rke2-master-server-lines = [for i in range(var.kube-master-count) : i == 0 ? "" : "server: https://${local.rke2-join-ip}:9345"]
}

#========================================

# Third create the EC2 Instance(s)
#----------------------------------

# The bastion's private_ip is calculated with cidrhost(), using the
# public subnet's CIDR (pub-sub-01-cidr) and a fixed host number
# (bastion-ip-host-num, see variables.tf) - this always resolves to .11
# in that subnet.

# Create Bastion Host in Public Subnet
resource "aws_instance" "bastion-01" {
  depends_on                  = [aws_route_table.pub-rt-01, aws_route_table_association.pub-rt-association-01, aws_key_pair.demo-ssh-key-pair-01]
  ami                         = data.aws_ami.ami-os.id
  instance_type               = var.bastion-node-size
  subnet_id                   = aws_subnet.pub-sub-01.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.pub-sg-01.id]
  private_ip                  = cidrhost(var.pub-sub-01-cidr, var.bastion-ip-host-num)
  key_name                    = aws_key_pair.demo-ssh-key-pair-01.key_name

  root_block_device {
    volume_size           = var.bastion-node-disk-size
    delete_on_termination = true
  }

  # Copy the private key onto the bastion so it can be used to jump to the private Kube nodes
  provisioner "file" {
    content     = tls_private_key.ssh-key-pair-local-01.private_key_pem
    destination = var.ssh-file-name
    connection {
      type        = "ssh"
      user        = var.ec2-user-name
      private_key = tls_private_key.ssh-key-pair-local-01.private_key_pem
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = ["chmod 400 ${var.ssh-file-name}"]
    connection {
      type        = "ssh"
      user        = var.ec2-user-name
      private_key = tls_private_key.ssh-key-pair-local-01.private_key_pem
      host        = self.public_ip
    }
  }

  # Copy the scripts folder to the ubuntu user's home directory
  provisioner "file" {
    source      = "k8s-scripts/"
    destination = "k8s-scripts"
    connection {
      type        = "ssh"
      user        = var.ec2-user-name
      private_key = tls_private_key.ssh-key-pair-local-01.private_key_pem
      host        = self.public_ip
    }
  }

  # Make every script executable
  provisioner "remote-exec" {
    inline = ["chmod +x k8s-scripts/* 2>/dev/null || true"]
    connection {
      type        = "ssh"
      user        = var.ec2-user-name
      private_key = tls_private_key.ssh-key-pair-local-01.private_key_pem
      host        = self.public_ip
    }
  }

  user_data = <<-EOT
    #!/bin/bash
    set -eo pipefail

    echo " ---- Starting CloudInit Script..."
    echo " ---------------------------------"
    echo ""

    log() { echo "$(date '+%F %T') [node-setup] $*"; }

    NODE_NAME=${local.bastion-name}

    # Set static hostname
    log "Setting hostname to $NODE_NAME ..."
    hostnamectl set-hostname --static "$NODE_NAME"
    log "Hostname set."

    # Add every node to /etc/hosts
    log "Editing /etc/hosts file ..."
    cat >> /etc/hosts <<'HOSTS'
    ${local.hosts-block}
    HOSTS
    log "/etc/hosts file edited."

    # Keep the hostname after reboot (AWS static hostname guide)
    log "Preserving hostname ..."
    echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
    log "Hostname preserved."

    sleep 10

    # Install kubectl
    # -----------------------
    log "Installing kubectl ..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x ./kubectl
    mv ./kubectl /usr/local/bin/kubectl
    log "--- kubectl installed."

    # Install Helm
    # -----------------------
    log "Installing Helm ..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log "--- Helm installed."

    echo " ---------------------------------"
    echo ""
    echo " ---- CloudInit Script Completed."
    echo " ---------------------------------"
  EOT

  tags = {
    Name       = local.bastion-name
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

# The number of master nodes comes from var.kube-master-count
# (variables.tf), which has a default but can be overridden. count turns
# this block into a loop of that many nodes, indexed 0 to count - 1. Each
# node's private_ip is cidrhost(priv-sub-01-cidr, kube-master-ip-start +
# count.index). Its Name tag and hostname both come from local.master-names
# (demo-kube-master-01, -02, ...).

# Create Kube Master Node(s) in Private Subnet
resource "aws_instance" "kube-master" {
  count                   = var.kube-master-count
  depends_on              = [aws_route_table.priv-rt-01, aws_route_table_association.priv-rt-association-01, aws_nat_gateway.main-natgw, aws_key_pair.demo-ssh-key-pair-01]
  ami                     = data.aws_ami.ami-os.id
  instance_type           = var.kube-master-node-size
  subnet_id               = aws_subnet.priv-sub-01.id
  vpc_security_group_ids  = [aws_security_group.priv-sg-01.id]
  private_ip              = cidrhost(var.priv-sub-01-cidr, var.kube-master-ip-start + count.index)
  key_name                = aws_key_pair.demo-ssh-key-pair-01.key_name

  root_block_device {
    volume_size           = var.kube-node-disk-size
    delete_on_termination = true
  }

  user_data = <<-EOT
    #!/bin/bash
    set -eo pipefail

    echo " ---- Starting CloudInit Script..."
    echo " ---------------------------------"
    echo ""

    log() { echo "$(date '+%F %T') [node-setup] $*"; }

    NODE_NAME=${local.master-names[count.index]}

    # Set static hostname
    log "Setting hostname to $NODE_NAME ..."
    hostnamectl set-hostname --static "$NODE_NAME"
    log "Hostname set."

    # Add every node to /etc/hosts
    log "Editing /etc/hosts file ..."
    cat >> /etc/hosts <<'HOSTS'
    ${local.hosts-block}
    HOSTS
    log "/etc/hosts file edited."

    # Keep the hostname after reboot (AWS static hostname guide)
    log "Preserving hostname ..."
    echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
    log "Hostname preserved."

    sleep 10

    # Install RKE2 - If enabled
    %{ if var.install-rke2 ~}
    # -----------------------
    log "Installing RKE2 ..."
    log "--- Creating rke2 folder ..."
    mkdir -p /etc/rancher/rke2/
    log "------ Folder created."
    log "--- Adding rke2 configuration to config file ..."
    cat <<EOF > /etc/rancher/rke2/config.yaml
    write-kubeconfig-mode: "0644"
    node-name: $NODE_NAME
    cni: "calico"
    cluster-cidr: "172.16.0.0/16"
    service-cidr: "172.17.0.0/16"
    token: ${random_password.rke2-token[0].result}
    ${local.rke2-master-server-lines[count.index]}
    tls-san:
      - ${local.rke2-join-ip}
    EOF
    log "------ Configuration added."
    log "--- Installing RKE2 using Quick Install Script ..."
    curl -sfL https://get.rke2.io | sh -
    log "------ RKE2 Quick Install Script completed."
    log "--- Enabling RKE2 server service ..."
    systemctl enable rke2-server.service --now
    log "------ Service enabled."

    sleep 10

    # kubectl access for the default OS user
    log "--- Configuring Kubeconfig file & permissions ..."
    mkdir -p /home/${var.ec2-user-name}/.kube
    cp /etc/rancher/rke2/rke2.yaml /home/${var.ec2-user-name}/.kube/config
    log "------ File created and kubeconfig copied."
    chown -R ${var.ec2-user-name}:${var.ec2-user-name} /home/${var.ec2-user-name}/.kube
    log "------ Permissions configured."
    echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /home/${var.ec2-user-name}/.bashrc
    log "------ PATH added."
    log "--------- RKE2 Installed."
    
    # Install Helm
    log "Installing Helm ..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log "--- Helm installed."
    # -----------------------
    %{ endif ~}

    echo " ---------------------------------"
    echo ""
    echo " ---- CloudInit Script Completed."
    echo " ---------------------------------"
  EOT

  tags = {
    Name       = local.master-names[count.index]
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}

# Same pattern as the master node(s) above, using kube-worker-count and
# kube-worker-ip-start instead.

# Create Kube Worker Node(s) in Private Subnet
resource "aws_instance" "kube-worker" {
  count                   = var.kube-worker-count
  depends_on              = [aws_route_table.priv-rt-01, aws_route_table_association.priv-rt-association-01, aws_nat_gateway.main-natgw, aws_key_pair.demo-ssh-key-pair-01]
  ami                     = data.aws_ami.ami-os.id
  instance_type           = var.kube-worker-node-size
  subnet_id               = aws_subnet.priv-sub-01.id
  vpc_security_group_ids  = [aws_security_group.priv-sg-01.id]
  private_ip              = cidrhost(var.priv-sub-01-cidr, var.kube-worker-ip-start + count.index)
  key_name                = aws_key_pair.demo-ssh-key-pair-01.key_name

  root_block_device {
    volume_size           = var.kube-node-disk-size
    delete_on_termination = true
  }

  user_data = <<-EOT
    #!/bin/bash
    set -eo pipefail

    echo " ---- Starting CloudInit Script..."
    echo " ---------------------------------"
    echo ""

    log() { echo "$(date '+%F %T') [node-setup] $*"; }

    NODE_NAME=${local.worker-names[count.index]}

    # Set static hostname
    log "Setting hostname to $NODE_NAME ..."
    hostnamectl set-hostname --static "$NODE_NAME"
    log "Hostname set."

    # Add every node to /etc/hosts
    log "Editing /etc/hosts file ..."
    cat >> /etc/hosts <<'HOSTS'
    ${local.hosts-block}
    HOSTS
    log "/etc/hosts file edited."

    # Keep the hostname after reboot (AWS static hostname guide)
    log "Preserving hostname ..."
    echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
    log "Hostname preserved."

    sleep 10

    # Install RKE2 - If enabled
    %{ if var.install-rke2 ~}
    # -----------------------
    log "Installing RKE2 (agent) ..."
    log "--- Creating rke2 folder ..."
    mkdir -p /etc/rancher/rke2/
    log "------ Folder created."
    log "--- Adding rke2 configuration to config file ..."
    cat <<EOF > /etc/rancher/rke2/config.yaml
    write-kubeconfig-mode: "0644"
    node-name: $NODE_NAME
    server: https://${local.rke2-join-ip}:9345
    token: ${random_password.rke2-token[0].result}
    EOF
    log "------ Configuration added."
    log "--- Installing RKE2 using Quick Install Script ..."
    curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -
    log "------ RKE2 Quick Install Script completed."
    log "--- Enabling RKE2 agent service ..."
    systemctl enable rke2-agent.service --now
    log "------ Service enabled."
    log "--------- RKE2 Installed."
    # -----------------------
    %{ endif ~}

    echo " ---------------------------------"
    echo ""
    echo " ---- CloudInit Script Completed."
    echo " ---------------------------------"
  EOT

  tags = {
    Name       = local.worker-names[count.index]
    DeployedBy = "TerraForm"
    UsedFor    = "K8sDemo"
    User       = "tshaker"
  }
}


# Write instance IDs and region for the power on/off scripts
resource "local_file" "instance-ids" {
  filename        = "${path.module}/start-stop-scripts/instance-ids.env"
  file_permission = "0644"
  content         = <<-EOT
    AWS_REGION="${var.aws-region}"
    BASTION_ID="${aws_instance.bastion-01.id}"
    MASTER_IDS=(${join(" ", aws_instance.kube-master[*].id)})
    WORKER_IDS=(${join(" ", aws_instance.kube-worker[*].id)})
  EOT
}

#========================================