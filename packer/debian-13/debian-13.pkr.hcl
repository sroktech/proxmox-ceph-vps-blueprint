locals {
  os_name      = "debian-13"
  template_ref = "tpl-${local.os_name}-${var.build_timestamp}-${var.git_sha}"
}

source "proxmox-iso" "debian" {
  proxmox_url              = var.proxmox_url
  node                     = var.proxmox_node
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_insecure

  vm_id                = 9002
  vm_name              = local.template_ref
  template_name        = local.template_ref
  template_description = "Debian 13 Trixie. Built ${var.build_timestamp} from ${var.git_sha}."

  qemu_agent      = true
  bios            = "ovmf"
  machine         = "q35"
  cpu_type        = "host"
  cores           = 2
  memory          = 2048
  os              = "l26"
  scsi_controller = "virtio-scsi-single"
  serials         = ["socket"]

  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = false
  }

  boot_iso {
    type             = "scsi"
    iso_url          = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.1.0-amd64-netinst.iso"
    iso_checksum     = "file:https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS"
    iso_storage_pool = var.iso_storage
    unmount          = true
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

  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  http_directory = "."
  boot_wait      = "5s"
  boot_command = [
    "<wait><down><wait>e<wait>",
    "<down><down><down><end>",
    " auto=true priority=critical url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "<f10>"
  ]

  ssh_username           = "packerbuild"
  ssh_private_key_file   = "~/.ssh/packer_build_ed25519"
  ssh_timeout            = "30m"
  ssh_handshake_attempts = 100
}

build {
  name    = "debian-13"
  sources = ["source.proxmox-iso.debian"]

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
  }
}
