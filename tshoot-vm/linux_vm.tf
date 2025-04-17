resource "azurerm_linux_virtual_machine" "this" {
  count                                                  = lower(var.os_type) == "linux" ? 1 : 0
  name                                                   = local.vm_name
  resource_group_name                                    = local.resource_group_name
  location                                               = local.resource_group_location
  size                                                   = local.vm_size
  admin_username                                         = var.admin_username
  admin_password                                         = var.admin_password
  disable_password_authentication                        = false
  network_interface_ids                                  = [azurerm_network_interface.this.id]
  patch_mode                                             = var.patch_mode
  bypass_platform_safety_checks_on_user_schedule_enabled = var.bypass_platform_safety_checks
  secure_boot_enabled                                    = var.secure_boot_enabled
  custom_data                                            = var.custom_cloud_init != null ? base64encode(var.custom_cloud_init) : (var.enable_cloud_init ? base64encode(local.default_cloud_init) : null)
  zone                                                   = var.zone
  tags                                                   = var.vm_tags
  boot_diagnostics {
    storage_account_uri = null
  }

  os_disk {
    caching              = var.os_disk_caching
    storage_account_type = var.os_disk_storage_account_type
  }

  source_image_reference {
    publisher = local.source_image_publisher
    offer     = local.source_image_offer
    sku       = local.source_image_sku
    version   = var.source_image_version
  }

  lifecycle {
    ignore_changes = [tags, identity, patch_assessment_mode]
  }
}

locals {
  default_cloud_init = <<-EOT
    #cloud-config
    package_update: true
    packages:
      - tcptraceroute
      - traceroute
      - net-tools
      - dnsutils
  EOT
}