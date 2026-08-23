variable "node_name" {
  type        = string
  description = "Node to place file resources on"
}

variable "snippet_datastore" {
  type        = string
  default     = "local"
  description = "Datastore with the snippets content type enabled"
}

variable "snippets" {
  type        = map(string)
  default     = {}
  description = "Map of filename => file content for cloud-init snippets"
}
