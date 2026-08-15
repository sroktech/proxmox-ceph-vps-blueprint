output "pools" {
  value       = module.pools.pool_ids
  description = "Resource pools managed by Terraform"
}

output "snippets" {
  value       = module.storage.snippet_ids
  description = "Uploaded cloud-init snippets"
}
