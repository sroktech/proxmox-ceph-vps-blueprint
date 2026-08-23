output "pool_ids" {
  value = keys(proxmox_virtual_environment_pool.this)
}
