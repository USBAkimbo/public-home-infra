# Decode CSV file
locals {
  vms_csv = csvdecode(file("./data/proxmox_vms.csv"))
}

# Create VM for each entry in CSV
resource "proxmox_vm_qemu" "proxmox_vm" {
  for_each = { for vm in local.vms_csv : vm.vm_name => vm }

  name                    = each.value.vm_name
  clone                   = each.value.clone
  target_node             = each.value.target_node
  onboot                  = each.value.start_on_boot
  startup                 = each.value.startup_order
  agent                   = each.value.agent
  os_type                 = each.value.os_type
  cores                   = each.value.vcpus
  memory                  = each.value.ram_in_mb
  ipconfig0               = each.value.ip_address
  cloudinit_cdrom_storage = each.value.cloudinit_cdrom_storage
  ciuser                  = each.value.ci_user
  nameserver              = each.value.nameserver
  sshkeys                 = each.value.ssh_keys
  scsihw                  = each.value.scsihw

  vga {
    type = each.value.display_adapter
  }

  disks {
    scsi {
      scsi0 {
        disk {
          backup  = each.value.backup
          size    = each.value.os_disk_size_in_gb
          storage = each.value.storage
        }
      }
    }
  }

  network {
    tag    = each.value.vlan_id
    model  = each.value.net_adapter_model
    bridge = each.value.net_switch
  }
}