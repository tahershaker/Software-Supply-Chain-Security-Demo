#######################################################
###  This Module will include the list of required  ###  
### Provider For this Terraform code to be executed ### 
#######################################################

#------------------------------------------------------


# First Add Required Providers and versions
#------------------------------------------

# List Required Providers
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

#========================================

# Second configure the added providers
#--------------------------------------

# Configure the AWS Provider
provider "aws" {
  region = var.aws-region
}
