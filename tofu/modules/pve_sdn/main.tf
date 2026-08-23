# SDN via OpenTofu: VERIFY PROVIDER COVERAGE FIRST.
#
#   tofu providers schema -json \
#     | jq -r '.provider_schemas[].resource_schemas | keys[]' | grep -i sdn
#
# EVPN-specific attributes (exit nodes, VRF VXLAN ID, controller peers) have
# historically lagged behind the API. If the resources you need are missing or
# immature, manage SDN through Ansible/pvesh and keep this module empty.
# Working infrastructure beats OpenTofu purity.
#
# Reference shape, adjust to your provider version's actual schema:
#
# resource "proxmox_virtual_environment_sdn_zone_evpn" "tenants" {
#   id                  = "tenants"
#   controller          = "evpnctl"
#   vrf_vxlan           = 4000
#   exit_nodes          = ["pve-01", "pve-02"]
#   mtu                 = 1500
#   advertise_subnets   = true
# }
#
# resource "proxmox_virtual_environment_sdn_vnet" "tenant" {
#   for_each = var.tenant_vnets
#   id       = each.key
#   zone     = proxmox_virtual_environment_sdn_zone_evpn.tenants.id
#   tag      = each.value.vni
# }
#
# IMPORTANT: per-tenant vnets are created and destroyed by CUSTOMER action
# (signup and cancellation). By the rule in docs/05, that makes them the
# panel's responsibility, not OpenTofu's. OpenTofu should own the ZONE and
# CONTROLLER only. This module intentionally does not manage per-tenant vnets.
