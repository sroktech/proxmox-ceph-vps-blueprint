# Least-privilege roles for the control panel and CI.
# The panel must NEVER use root@pam: one panel compromise would otherwise
# become every customer's compromise.

resource "proxmox_virtual_environment_role" "this" {
  for_each   = var.roles
  role_id    = each.key
  privileges = each.value
}

resource "proxmox_virtual_environment_user" "this" {
  for_each = var.users

  user_id = each.key
  comment = each.value.comment
  enabled = each.value.enabled
  # Expiry on service accounts forces rotation. Monitor it, or provisioning
  # will fail silently at the worst moment.
  expiration_date = each.value.expiration_date
}

resource "proxmox_virtual_environment_acl" "this" {
  for_each = var.acls

  user_id   = each.value.user_id
  role_id   = each.value.role_id
  path      = each.value.path
  propagate = each.value.propagate

  depends_on = [
    proxmox_virtual_environment_role.this,
    proxmox_virtual_environment_user.this,
  ]
}
