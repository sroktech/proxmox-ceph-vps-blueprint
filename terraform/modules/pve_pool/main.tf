resource "proxmox_virtual_environment_pool" "this" {
  for_each = var.pools

  pool_id = each.key
  comment = each.value

  lifecycle {
    # A pool is a container for customer VMs. Destroying it is never something
    # a routine plan should do.
    prevent_destroy = true
  }
}
