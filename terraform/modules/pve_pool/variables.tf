variable "pools" {
  type        = map(string)
  description = "Map of pool_id => comment"
  default     = {}
}
