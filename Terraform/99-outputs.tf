#######################################################
###     This Module will hold the values of the     ###
###    required output for the deployed resources   ###  
#######################################################
#
# NOTE: these outputs show you how to reach and manage this environment
# after it's deployed - bastion address, load balancer address, SSH key
# location, and every node's IP. If you close this terminal, run
# `terraform output` again any time to see these same values.
#
# NOTE: kube-master-nodes and kube-worker-nodes list every node that was
# created. Master and worker counts have defaults, but can be changed by
# the user, so how many nodes appear here varies depending on what
# kube-master-count and kube-worker-count were set to at apply time.
#
# NOTE: instance IDs are listed for every EC2 instance. The same IDs are
# saved to start-stop-scripts/instance-ids.env (written by 10-compute.tf)
# for the ec2-power-off.sh and ec2-power-on.sh scripts in that folder,
# which stop and start the whole environment to save cost.
#
#------------------------------------------------------

# Node IP and ID lines, built once here so the summary block below can reuse them
locals {
  master-lines = join("\n", [for inst in aws_instance.kube-master : "  - ${inst.tags["Name"]}: IP=${inst.private_ip}  ID=${inst.id}"])
  worker-lines = join("\n", [for inst in aws_instance.kube-worker : "  - ${inst.tags["Name"]}: IP=${inst.private_ip}  ID=${inst.id}"])
  kube-api-lb-ip = local.create-api-nlb ? cidrhost(var.priv-sub-01-cidr, 10) : "n/a (single master cluster)"
}

output "bastion-fqdn" {
  value = aws_eip.bastion-eip.public_dns
}

output "bastion-public-ip" {
  value = aws_eip.bastion-eip.public_ip
}

output "bastion-private-ip" {
  value = aws_instance.bastion-01.private_ip
}

output "bastion-id" {
  value = aws_instance.bastion-01.id
}

output "lb-fqdn" {
  value = aws_lb.nlb-01.dns_name
}

output "lb-public-ip" {
  value = aws_eip.lb-eip.public_ip
}

# Internal address of the Kubernetes API load balancer. Enter this when the
# first master script asks for the Load Balancer IP. Only exists with 3 masters.
output "kube-api-lb-ip" {
  value = local.kube-api-lb-ip
}

output "k8s-scripts-path-on-bastion" {
  value = "/home/${var.ec2-user-name}/k8s-scripts"
}

# The AWS-registered key pair name, and the local file it's saved to.
# The local filename has a random prefix, added in 10-compute.tf, so
# repeated deployments never collide with an old key file.
output "ssh-key-name-and-local-path" {
  value = "${aws_key_pair.demo-ssh-key-pair-01.key_name}  (local file: ${random_string.ssh-key-random.result}-${var.ssh-file-name})"
}

# The filename and path the key is copied to ON the bastion itself -
# note this has no random prefix, unlike the local copy above, since the
# bastion's "file" provisioner in 10-compute.tf writes it as plain
# var.ssh-file-name into the login user's home directory.
output "ssh-key-name-and-path-on-bastion" {
  value = "/home/${var.ec2-user-name}/${var.ssh-file-name}"
}

# One entry per master node - name and private IP.
output "kube-master-nodes" {
  value = {
    for inst in aws_instance.kube-master : inst.tags["Name"] => inst.private_ip
  }
}

# One entry per worker node - name and private IP.
output "kube-worker-nodes" {
  value = {
    for inst in aws_instance.kube-worker : inst.tags["Name"] => inst.private_ip
  }
}

# Every EC2 instance ID - the same values saved to instance-ids.env.
output "ec2-instance-ids" {
  value = {
    bastion = aws_instance.bastion-01.id
    masters = { for inst in aws_instance.kube-master : inst.tags["Name"] => inst.id }
    workers = { for inst in aws_instance.kube-worker : inst.tags["Name"] => inst.id }
  }
}

output "Deployment-Outputs" {
  value = <<EOF

  ╔══════════════════════════════════════════════════════╗
  ║                                                      ║
  ║        PROVISIONING COMPLETED SUCCESSFULLY           ║
  ║                                                      ║
  ╚══════════════════════════════════════════════════════╝

  ========================================================
  Resource and information outputs for this deployment:
  ========================================================
  - Bastion Host FQDN:                          ${aws_eip.bastion-eip.public_dns}
  - Bastion Host Public IP:                     ${aws_eip.bastion-eip.public_ip}
  - Bastion Host Private IP:                    ${aws_instance.bastion-01.private_ip}
  - Bastion Host Instance ID:                   ${aws_instance.bastion-01.id}
  - Load Balancer FQDN:                         ${aws_lb.nlb-01.dns_name}
  - Load Balancer Public IP:                    ${aws_eip.lb-eip.public_ip}
    - Kube API Load Balancer IP (3 masters):    ${local.kube-api-lb-ip}
  - SSH Key Name:                               ${aws_key_pair.demo-ssh-key-pair-01.key_name}
  - SSH Key Local Path:                         ${random_string.ssh-key-random.result}-${var.ssh-file-name}
  - SSH Key Path on Bastion:                    /home/${var.ec2-user-name}/${var.ssh-file-name}
  - Script Folder Path on Bastion:              /home/${var.ec2-user-name}/k8s-scripts

  ----------------------------------------------------------

  Kube Master Node(s):
${local.master-lines}

  ----------------------------------------------------------

  Kube Worker Node(s):
${local.worker-lines}

  ----------------------------------------------------------

  Stop / start the whole environment to save cost:
    ./start-stop-scripts/ec2-power-off.sh   (stops all EC2 instances)
    ./start-stop-scripts/ec2-power-on.sh    (starts them again)
  Both read instance-ids.env from the same folder, which this deployment
  writes for you. Run them from the Terraform folder, using the same AWS
  credentials.
  Note: the NAT gateway, load balancer and disks are still billed
  whilst the instances are stopped.

  ----------------------------------------------------------

  =================================================================
  NOTE: this information is needed to connect to and manage this
  environment (SSH access, node IPs, load balancer address). It is
  recommended you save it somewhere before closing this terminal.

  You can also see it again any time by running: terraform output
  =================================================================

  ╔══════════════════════════════════════════════════════╗
  ║                                                      ║
  ║              END OF DEPLOYMENT OUTPUT                ║
  ║                                                      ║
  ╚══════════════════════════════════════════════════════╝
  
  EOF
}