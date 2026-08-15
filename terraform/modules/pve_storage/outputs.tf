output "snippet_ids" {
  value       = { for k, v in proxmox_virtual_environment_file.snippets : k => v.id }
  description = "Uploaded snippet resource IDs"
}
