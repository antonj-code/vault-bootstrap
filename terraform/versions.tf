terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.66.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "= 2.5.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "= 4.0.6"
    }
  }

  # Configured for GitLab Managed Terraform State
  # Credentials and URLs injected via CI/CD environment variables:
  # TF_HTTP_ADDRESS, TF_HTTP_LOCK_ADDRESS, TF_HTTP_UNLOCK_ADDRESS, TF_HTTP_USERNAME, TF_HTTP_PASSWORD
  backend "http" {}
}
