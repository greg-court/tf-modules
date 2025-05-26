resource "null_resource" "provision_bind_options" {
  # Trigger replacement if the content changes
  triggers = {
    content_sha1 = sha1(var.bind_named_conf_options_content)
    vm_id        = azurerm_linux_virtual_machine.nva.id # Ensure VM exists
  }

  provisioner "file" {
    content     = var.bind_named_conf_options_content
    destination = "/tmp/named.conf.options.tmp"

    connection {
      type     = "ssh"
      user     = var.admin_username
      password = var.admin_password
      host     = azurerm_public_ip.pip.ip_address # Assumes pip is created before this null_resource implicitly
      timeout  = "1m"
      agent    = false
    }
  }
  depends_on = [null_resource.add_temp_ssh_rule]
}

resource "null_resource" "provision_bind_local" {
  triggers = {
    content_sha1 = sha1(var.bind_named_conf_local_content)
    vm_id        = azurerm_linux_virtual_machine.nva.id
  }

  provisioner "file" {
    content     = var.bind_named_conf_local_content
    destination = "/tmp/named.conf.local.tmp"

    connection {
      type     = "ssh"
      user     = var.admin_username
      password = var.admin_password
      host     = azurerm_public_ip.pip.ip_address
      timeout  = "1m"
      agent    = false
    }
  }
  depends_on = [null_resource.add_temp_ssh_rule]
}

resource "null_resource" "provision_bind_primary_zone" {
  triggers = {
    content_sha1 = sha1(var.bind_primary_zone_file_content)
    path         = var.bind_primary_zone_file_path
    vm_id        = azurerm_linux_virtual_machine.nva.id
  }

  provisioner "file" {
    content     = var.bind_primary_zone_file_content
    destination = "/tmp/db.azlocal.tmp"

    connection {
      type     = "ssh"
      user     = var.admin_username
      password = var.admin_password
      host     = azurerm_public_ip.pip.ip_address
      timeout  = "1m"
      agent    = false
    }
  }
  depends_on = [null_resource.add_temp_ssh_rule]
}