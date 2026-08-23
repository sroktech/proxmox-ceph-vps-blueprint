variable "controller_asn" {
  type    = number
  default = 65000
}

variable "controller_peers" {
  type        = list(string)
  description = "VXLAN underlay addresses of all nodes"
  default     = []
}

variable "exit_nodes" {
  type        = list(string)
  description = "Nodes that route tenant traffic to the internet"
  default     = []
}

variable "vrf_vxlan_id" {
  type    = number
  default = 4000
}

variable "tenant_mtu" {
  type        = number
  default     = 1500
  description = "1500 requires a 9000-byte underlay. Use 1450 with a 1500 underlay."
}
