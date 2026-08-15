variable "proxmox_url" {
  type        = string
  description = "PVE API endpoint, e.g. https://10.10.10.11:8006/api2/json"
}

variable "proxmox_node" {
  type        = string
  description = "Node to build on"
  default     = "pve-01"
}

variable "proxmox_username" {
  type        = string
  description = "API token ID, e.g. packer@pve!builder"
}

variable "proxmox_token" {
  type        = string
  sensitive   = true
  description = "API token secret. Supply via PKR_VAR_proxmox_token from SOPS."
}

variable "proxmox_insecure" {
  type    = bool
  default = false
}

variable "storage_pool" {
  type    = string
  default = "vm-disks"
}

variable "iso_storage" {
  type    = string
  default = "local"
}

variable "network_bridge" {
  type        = string
  description = "Bridge with DHCP + internet access for the build VM only"
  default     = "vmbr0"
}

variable "build_ssh_public_key" {
  type        = string
  description = "Ephemeral build key public half. Removed during cleanup."
}

variable "build_timestamp" {
  type        = string
  description = "YYYYMMDD, injected by CI"
}

variable "git_sha" {
  type        = string
  description = "Short commit SHA, injected by CI"
}
