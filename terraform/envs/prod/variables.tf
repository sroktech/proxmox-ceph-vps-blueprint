variable "pve_endpoint" {
  type        = string
  description = "PVE API endpoint, e.g. https://pve-01.dc1.example.net:8006/"
}

variable "pve_api_token" {
  type        = string
  sensitive   = true
  description = "Scoped API token. Injected from SOPS in CI, never in tfvars."
}

variable "primary_node" {
  type    = string
  default = "pve-01"
}

variable "cluster_nodes" {
  type    = list(string)
  default = ["pve-01", "pve-02", "pve-03"]
}

variable "vxlan_underlay_peers" {
  type    = list(string)
  default = ["10.10.40.11", "10.10.40.12", "10.10.40.13"]
}

variable "sdn_exit_nodes" {
  type    = list(string)
  default = ["pve-01", "pve-02"]
}
