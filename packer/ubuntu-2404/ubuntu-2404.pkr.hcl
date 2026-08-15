# Ubuntu 24.04 LTS cloud-init template.
# Build:  packer build -var-file=../common.pkrvars.hcl .
#
# VMID range 9000-9099 is reserved for templates so it can never collide
# with customer VMs (100-8999).

locals {
  os_name      = "ubuntu-2404"
  template_ref = "tpl-${local.os_name}-${var.build_timestamp}-${var.git_sha}"
}

source "proxmox-iso" "ubuntu" {
  proxmox_url              = var.proxmox_url
  node                     = var.proxmox_node
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_insecure

  vm_id                = 9001
  vm_name              = local.template_ref
  template_name        = local.template_ref
  template_description = "Ubuntu 24.04 LTS. Built ${var.build_timestamp} from ${var.git_sha}. Do not edit by hand."

  # --- Guest hardware ---
  qemu_agent = true
  bios       = "ovmf"
  machine    = "q35"
  cpu_type   = "host"
  cores      = 2
  sockets    = 1
  memory     = 2048
  os         = "l26"
  scsi_controller = "virtio-scsi-single"

  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = false
  }

  # Serial console: the single biggest support-ticket reducer.
  serials = ["socket"]

  boot_iso {
    type         = "scsi"
    iso_url      = "https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso"
    iso_checksum = "file:https://releases.ubuntu.com/24.04/SHA256SUMS"
    iso_storage_pool = var.iso_storage
    unmount      = true
  }

  disks {
    disk_size    = "8G"
    storage_pool = var.storage_pool
    type         = "scsi"
    format       = "raw"
    cache_mode   = "none"
    io_thread    = true
    discard      = true
    ssd          = true
  }

  network_adapters {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = false
  }

  # cloud-init drive: how the panel injects customer keys and network config
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # --- Autoinstall ---
  http_directory = "http"
  boot_wait      = "5s"
  boot_command = [
    "<wait>c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]

  ssh_username         = "packerbuild"
  ssh_private_key_file = "~/.ssh/packer_build_ed25519"
  ssh_timeout          = "30m"
  ssh_handshake_attempts = 100
}

build {
  name    = "ubuntu-2404"
  sources = ["source.proxmox-iso.ubuntu"]

  provisioner "shell" {
    execute_command = "sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
    scripts = [
      "../scripts/00-wait-cloud-init.sh",
      "../scripts/10-base-packages-deb.sh",
      "../scripts/20-serial-console-deb.sh",
      "../scripts/40-harden-deb.sh",
      "../scripts/30-cloud-init-reset.sh",
      "../scripts/99-cleanup.sh",
    ]
  }

  post-processor "manifest" {
    output     = "manifest-${local.os_name}.json"
    strip_path = true
    custom_data = {
      os       = local.os_name
      template = local.template_ref
      git_sha  = var.git_sha
      built    = var.build_timestamp
    }
  }
}
