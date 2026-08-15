# Storage definitions are platform config: few, slow-changing, shared.
# Exactly the profile Terraform is good at.

resource "proxmox_virtual_environment_file" "snippets" {
  for_each     = var.snippets
  content_type = "snippets"
  datastore_id = var.snippet_datastore
  node_name    = var.node_name

  source_raw {
    data      = each.value
    file_name = each.key
  }
}

# NOTE: RBD/PBS storage resources may not be covered by every provider version.
# Verify before relying on them:
#   terraform providers schema -json | jq -r '.provider_schemas[].resource_schemas | keys[]'
# If a resource is missing, manage that storage via Ansible (pvesh) and remove
# it from Terraform rather than fighting the provider.
