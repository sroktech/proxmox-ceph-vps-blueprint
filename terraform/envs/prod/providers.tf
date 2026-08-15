terraform {
  required_version = ">= 1.9"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # Pin EXACTLY. This provider has had breaking schema changes between
      # minor versions. Read the changelog before bumping.
      version = "0.66.1"
    }
  }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token
  # insecure = true would make the runner accept any certificate, defeating
  # TLS on your control path. Use PVE's ACME integration or an internal CA.
  insecure = false

  ssh {
    agent    = true
    username = "root"
  }
}
