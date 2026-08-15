variable "roles" {
  type        = map(list(string))
  description = "Map of role_id => list of privileges"
  default     = {}
}

variable "users" {
  type = map(object({
    comment         = string
    enabled         = bool
    expiration_date = optional(string)
  }))
  description = "Map of user_id (e.g. panel@pve) => attributes"
  default     = {}
}

variable "acls" {
  type = map(object({
    user_id   = string
    role_id   = string
    path      = string
    propagate = bool
  }))
  description = "ACL assignments"
  default     = {}
}
