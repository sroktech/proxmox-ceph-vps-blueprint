# ============================================================================
# Platform-level configuration only.
#
# HARD RULE: no customer VM resources in this configuration, ever.
#   - state locking serialises provisioning
#   - a bad plan or a misdirected destroy could queue deletion of every VM
#   - customer-initiated changes (resize, rebuild) look like drift
# Customer VMs are created by the control panel calling the Proxmox API.
# Boundary test: would a customer's action ever change this resource? If yes,
# it does not belong here.
# ============================================================================

module "pools" {
  source = "../../modules/pve_pool"

  pools = {
    "customers-shared"  = "Shared-tier customer VMs"
    "customers-premium" = "Premium-tier customer VMs"
    "infrastructure"    = "Platform VMs: monitoring, panel, runners"
    "templates"         = "OS templates, VMID 9000-9099"
  }
}

module "api_access" {
  source = "../../modules/pve_api_user"

  roles = {
    # The panel needs to create, configure, and destroy guests, and read
    # storage. It must NOT be able to change cluster, Ceph, or SDN config.
    "PanelProvisioner" = [
      "VM.Allocate",
      "VM.Clone",
      "VM.Config.CDROM",
      "VM.Config.CPU",
      "VM.Config.Cloudinit",
      "VM.Config.Disk",
      "VM.Config.HWType",
      "VM.Config.Memory",
      "VM.Config.Network",
      "VM.Config.Options",
      "VM.Console",
      "VM.Monitor",
      "VM.PowerMgmt",
      "VM.Audit",
      "Datastore.AllocateSpace",
      "Datastore.Audit",
      "SDN.Use",
      "Pool.Audit",
    ]

    # CI needs to read everything and manage templates. Not customer VMs.
    "CIReadOnly" = [
      "VM.Audit",
      "Datastore.Audit",
      "Sys.Audit",
      "Pool.Audit",
      "SDN.Audit",
    ]

    # Packer needs to build and template VMs in the template VMID range.
    "ImageBuilder" = [
      "VM.Allocate",
      "VM.Clone",
      "VM.Config.CDROM",
      "VM.Config.CPU",
      "VM.Config.Cloudinit",
      "VM.Config.Disk",
      "VM.Config.HWType",
      "VM.Config.Memory",
      "VM.Config.Network",
      "VM.Config.Options",
      "VM.Console",
      "VM.Monitor",
      "VM.PowerMgmt",
      "VM.Audit",
      "Datastore.Allocate",
      "Datastore.AllocateSpace",
      "Datastore.AllocateTemplate",
      "Datastore.Audit",
    ]
  }

  users = {
    "panel@pve" = {
      comment         = "Control panel service account. Managed by OpenTofu."
      enabled         = true
      expiration_date = null
    }
    "ci@pve" = {
      comment         = "GitLab CI service account. Managed by OpenTofu."
      enabled         = true
      expiration_date = null
    }
    "packer@pve" = {
      comment         = "Packer image builder. Managed by OpenTofu."
      enabled         = true
      expiration_date = null
    }
  }

  acls = {
    "panel-shared" = {
      user_id   = "panel@pve"
      role_id   = "PanelProvisioner"
      path      = "/pool/customers-shared"
      propagate = true
    }
    "panel-premium" = {
      user_id   = "panel@pve"
      role_id   = "PanelProvisioner"
      path      = "/pool/customers-premium"
      propagate = true
    }
    "packer-templates" = {
      user_id   = "packer@pve"
      role_id   = "ImageBuilder"
      path      = "/pool/templates"
      propagate = true
    }
    "ci-readonly" = {
      user_id   = "ci@pve"
      role_id   = "CIReadOnly"
      path      = "/"
      propagate = true
    }
  }
}

module "storage" {
  source = "../../modules/pve_storage"

  node_name         = var.primary_node
  snippet_datastore = "local"

  snippets = {
    # Baseline vendor-data applied to every customer VM in addition to the
    # per-VM user-data the panel generates.
    "vendor-baseline.yaml" = <<-EOT
      #cloud-config
      package_update: true
      timezone: UTC
      ntp:
        enabled: true
      growpart:
        mode: auto
        devices: ['/']
        ignore_growroot_disabled: false
      resize_rootfs: true
    EOT
  }
}

# SDN: verify provider coverage before enabling. See module comments.
# module "sdn" {
#   source           = "../../modules/pve_sdn"
#   controller_peers = var.vxlan_underlay_peers
#   exit_nodes       = var.sdn_exit_nodes
#   tenant_mtu       = 1500
# }
