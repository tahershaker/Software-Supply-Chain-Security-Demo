#!/usr/bin/env bash
#------------------

#-------------------------------------------------------------
# Script Description
#-------------------------------------------------------------

################################################################################
# This script stops every EC2 instance created by the Terraform deployment.
# Stopped instances keep their disks and fixed private IPs, and stop
# charging for compute.
#
# The instances are handled in this order: bastion node, then master node(s),
# then worker node(s).
#
# The instance IDs and the AWS region are read from instance-ids.env, which
# Terraform writes during terraform apply. This file must be in the same
# folder as this script.
#
# Usage:  ./ec2-power-off.sh
# Needs:  AWS CLI, with the same credentials/profile you use for Terraform.
################################################################################

#=========================================================================================

#-------------------------------------------------------------
# Strict bash safety + error/interrupt traps
#-------------------------------------------------------------

# -E: ERR trap inherits into functions/subshells | -e: exit on any failed command
# -u: unset variables are errors | -o pipefail: pipeline fails if any stage fails
set -Eeuo pipefail

# Catch Ctrl+C / kill signals and exit with a clean message instead of dying silently
trap 'echo -e "\n ---- Script interrupted. Exiting..."; exit 1' INT TERM

# Catch any failure triggered by set -e and print the line + command that caused it
trap 'rc=$?; echo -e "\n ---- ERROR: line ${LINENO}: ${BASH_COMMAND}" >&2; exit $rc' ERR

#=========================================================================================

#-------------------------------------------------------------
# Set Colors For Outputs
#-------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'   # Reset / No Color

# Output levels used in this script (colour + indentation):
#   Level 0 - Part heading          : GREEN,  1 space, underlined
#   Level 1 - Step                  : YELLOW, 1 space + " - "
#   Level 2 - Per-instance action   : CYAN,   3 spaces
#   Level 3 - Result / state        : CYAN,   6 spaces
#   Final success message           : GREEN,  3 spaces
#   Errors                          : RED

#=========================================================================================

#-------------------------------------------------------------
# Locate The Instance Info File
#-------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/instance-ids.env"

#=========================================================================================

#-------------------------------------------------------------
# Create bannar & Print Starting Script Message
#-------------------------------------------------------------

echo -e "${GREEN}"
echo "  ---------------------------------------------------------------------  "
echo " | =================================================================== | "
echo " |                       EC2 Instances Power Off                       | "
echo " | ------------------------------------------------------------------- | "
echo " |                                                                     | "
echo " |            Stops every EC2 instance created by Terraform            | "
echo " |                                                                     | "
echo "  ---------------------------------------------------------------------  "
echo ""
echo " --- Starting the EC2 power-off script..."
echo -e "${NC}"

echo " ================================================================================== "
echo ""

#=========================================================================================

#-------------------------------------------------------------
# Load The Instance Info
#-------------------------------------------------------------

echo -e "${GREEN} Part 1: - Load Instance Info:${NC}"
echo -e "${GREEN} -----------------------------${NC}"
echo ""

echo -e "${YELLOW} - Checking the instance info file...${NC}"

# Exit if the file written by Terraform does not exist
if [[ ! -f "${ENV_FILE}" ]]; then
  echo ""
  echo -e "${RED} ------------------------------------------------------------------------------------${NC}"
  echo -e "${RED} ---- ERROR: the file ${ENV_FILE} does not exist.${NC}"
  echo -e "${RED} ---- Make sure the file exists in this path and that the Terraform deployment (terraform apply) created it.${NC}"
  echo -e "${RED} ------------------------------------------------------------------------------------${NC}"
  echo ""
  exit 1
fi

echo -e "${CYAN}   Found: ${ENV_FILE}${NC}"

# Load AWS_REGION, BASTION_ID, MASTER_IDS and WORKER_IDS from the file
# shellcheck source=/dev/null
source "${ENV_FILE}"

# Every instance ID, used at the end to wait until all are stopped
ALL_IDS=("${BASTION_ID}" "${MASTER_IDS[@]}" "${WORKER_IDS[@]}")

echo -e "${CYAN}   Loaded ${#ALL_IDS[@]} instance(s) in region ${AWS_REGION}.${NC}"

#=========================================================================================

#-------------------------------------------------------------
# Stop The Instances (Bastion, Master Node(s), Worker Node(s))
#-------------------------------------------------------------

echo ""
echo -e "${GREEN} Part 2: - Stop Instances:${NC}"
echo -e "${GREEN} -------------------------${NC}"
echo ""

# --- Bastion node ---
echo -e "${YELLOW} - Stopping Bastion node${NC}"
echo -e "${CYAN}   Stopping ${BASTION_ID} ...${NC}"
state=$(aws ec2 stop-instances --region "${AWS_REGION}" --instance-ids "${BASTION_ID}" \
  --query 'StoppingInstances[0].CurrentState.Name' --output text)
echo -e "${CYAN}      State: ${state}${NC}"
echo ""

# --- Master node(s) ---
echo ""
echo -e "${YELLOW} - Stopping Master node(s)${NC}"
for id in "${MASTER_IDS[@]}"; do
  echo -e "${CYAN}   Stopping ${id} ...${NC}"
  state=$(aws ec2 stop-instances --region "${AWS_REGION}" --instance-ids "${id}" \
    --query 'StoppingInstances[0].CurrentState.Name' --output text)
  echo -e "${CYAN}      State: ${state}${NC}"
  echo ""
done

# --- Worker node(s) ---
echo ""
echo -e "${YELLOW} - Stopping Worker node(s)${NC}"
for id in "${WORKER_IDS[@]}"; do
  echo -e "${CYAN}   Stopping ${id} ...${NC}"
  state=$(aws ec2 stop-instances --region "${AWS_REGION}" --instance-ids "${id}" \
    --query 'StoppingInstances[0].CurrentState.Name' --output text)
  echo -e "${CYAN}      State: ${state}${NC}"
  echo ""
done

#=========================================================================================

#-------------------------------------------------------------
# Wait Until All Instances Reach The New State
#-------------------------------------------------------------

echo ""
echo -e "${GREEN} Part 3: - Wait For Instances To Stop:${NC}"
echo -e "${GREEN} -------------------------------------${NC}"
echo ""

echo -e "${YELLOW} - Waiting for all instances to reach the stopped state...${NC}"
aws ec2 wait instance-stopped --region "${AWS_REGION}" --instance-ids "${ALL_IDS[@]}"
echo -e "${GREEN}   SUCCESS: all instances are stopped.${NC}"

#=========================================================================================

echo ""
echo -e "${GREEN} ==================================================${NC}"

echo ""
echo -e "${GREEN} Power-off completed successfully${NC}"
echo -e "${GREEN} --------------------------------${NC}"
echo ""
echo -e "${YELLOW} - Note: the NAT gateway, load balancer, disks and public IPv4 addresses are still billed whilst the instances are stopped.${NC}"
echo ""
echo -e "${GREEN} ==================================================${NC}"

#=========================================================================================
