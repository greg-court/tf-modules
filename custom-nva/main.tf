#################### filename: custom-nva/main.tf ####################

terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

resource "azurerm_public_ip" "pip" {
  name                = "${var.vm_name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "untrust_nic" {
  name                  = "${var.vm_name}-nic-untrust"
  location              = var.location
  resource_group_name   = var.resource_group_name
  tags                  = var.tags
  ip_forwarding_enabled = true # Crucial for routing

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.untrust_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(data.azurerm_subnet.untrust_subnet_details.address_prefixes[0], 4)
    public_ip_address_id          = azurerm_public_ip.pip.id
    primary                       = true # Mark as primary
  }
}

resource "azurerm_network_interface" "trust_nic" {
  name                  = "${var.vm_name}-nic-trust"
  location              = var.location
  resource_group_name   = var.resource_group_name
  tags                  = var.tags
  ip_forwarding_enabled = true # Crucial for routing

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.trust_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(data.azurerm_subnet.trust_subnet_details.address_prefixes[0], 4)
  }
}

data "azurerm_subnet" "trust_subnet_details" {
  resource_group_name  = split("/", var.trust_subnet_id)[4]
  virtual_network_name = split("/", var.trust_subnet_id)[8]
  name                 = split("/", var.trust_subnet_id)[10]
}

data "azurerm_subnet" "untrust_subnet_details" {
  resource_group_name  = split("/", var.untrust_subnet_id)[4]
  virtual_network_name = split("/", var.untrust_subnet_id)[8]
  name                 = split("/", var.untrust_subnet_id)[10]
}

locals {
  wg_network_address = cidrhost(var.wg_server_address_cidr, 0)
  wg_network_prefix  = split("/", var.wg_server_address_cidr)[1]
  wg_subnet_cidr     = "${local.wg_network_address}/${local.wg_network_prefix}"

  peer_tunnel_ip_list                 = var.wg_peer_allowed_ips_cidr != "" ? [var.wg_peer_allowed_ips_cidr] : []
  combined_peer_ips_list              = compact(concat(local.peer_tunnel_ip_list, var.routing_ranges_onprem)) # Changed variable name
  wg_peer_combined_allowed_ips_string = join(",", local.combined_peer_ips_list)

  disable_password_auth = false
  admin_pass_to_use     = var.admin_password != null ? var.admin_password : null

  routing_ranges_onprem_str = join(" ", var.routing_ranges_onprem)
  routing_ranges_azure_str  = join(" ", var.routing_ranges_azure)

  trust_subnet_base_cidr  = data.azurerm_subnet.trust_subnet_details.address_prefixes[0]
  trust_subnet_gateway_ip = cidrhost(local.trust_subnet_base_cidr, 1)
  template_vars = {
    wg_server_private_key        = var.wg_server_private_key
    wg_server_address_cidr       = var.wg_server_address_cidr
    wg_listen_port               = var.wg_listen_port
    wg_peer_public_key           = var.wg_peer_public_key
    wg_peer_allowed_ips_cidr     = var.wg_peer_allowed_ips_cidr
    wg_peer_combined_allowed_ips = local.wg_peer_combined_allowed_ips_string

    untrust_iface_name      = var.untrust_interface_name
    trust_iface_name        = var.trust_interface_name
    trust_subnet_cidr       = data.azurerm_subnet.trust_subnet_details.address_prefixes[0]
    trust_subnet_gateway_ip = local.trust_subnet_gateway_ip
    wg_actual_subnet_cidr   = local.wg_subnet_cidr

    routing_ranges_onprem_str = local.routing_ranges_onprem_str
    routing_ranges_azure_str  = local.routing_ranges_azure_str

    on_prem_source_ip = var.on_prem_source_ip # used to allow ssh access from on prem ip only

    enable_bind_server              = lower(tostring(var.enable_bind_server))
    bind_primary_zone_file_path     = var.bind_primary_zone_file_path
  }
}

resource "azurerm_linux_virtual_machine" "nva" {
  name                = var.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }
  disable_password_authentication = local.disable_password_auth # Using local for clarity
  admin_password                  = local.admin_pass_to_use     # Using local for clarity

  tags = var.tags

  network_interface_ids = [
    azurerm_network_interface.untrust_nic.id,
    azurerm_network_interface.trust_nic.id,
  ]

  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "minimal"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  boot_diagnostics {}

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yml", {}))
}

resource "null_resource" "provision_bind_options" {
  # Trigger replacement if the content changes
  triggers = {
    content_sha1 = sha1(var.bind_named_conf_options_content)
    vm_id        = azurerm_linux_virtual_machine.nva.id # Ensure VM exists
  }

  provisioner "file" {
    content     = var.bind_named_conf_options_content
    destination = "/tmp/named.conf.options.tmp" # Place in /tmp for script to move

    connection {
      type        = "ssh"
      user        = var.admin_username
      password    = var.admin_password
      host        = azurerm_public_ip.pip.ip_address # Assumes pip is created before this null_resource implicitly
      timeout     = "5m"
      agent       = false
    }
  }
  depends_on = [azurerm_linux_virtual_machine.nva] # Explicit dependency
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
      type        = "ssh"
      user        = var.admin_username
      password    = var.admin_password
      host        = azurerm_public_ip.pip.ip_address
      timeout     = "5m"
      agent       = false
    }
  }
  depends_on = [azurerm_linux_virtual_machine.nva]
}

resource "null_resource" "provision_bind_primary_zone" {
  triggers = {
    content_sha1 = sha1(var.bind_primary_zone_file_content)
    path         = var.bind_primary_zone_file_path # Include path if it could change and affect destination logic
    vm_id        = azurerm_linux_virtual_machine.nva.id
  }

  provisioner "file" {
    content     = var.bind_primary_zone_file_content
    destination = "/tmp/db.azlocal.tmp" # Fixed temp name, script will use var.bind_primary_zone_file_path for final move

    connection {
      type        = "ssh"
      user        = var.admin_username
      password    = var.admin_password
      host        = azurerm_public_ip.pip.ip_address
      timeout     = "5m"
      agent       = false
    }
  }
  depends_on = [azurerm_linux_virtual_machine.nva]
}

resource "terraform_data" "nva_config_trigger" {
  input = sha1(jsonencode({
    script_content_hash            = filesha1("${path.module}/apply_nva_config.sh")
    template_variables_hash        = sha1(jsonencode(local.template_vars))
    bind_options_content_hash      = sha1(var.bind_named_conf_options_content)
    bind_local_content_hash        = sha1(var.bind_named_conf_local_content)
    bind_primary_zone_content_hash = sha1(var.bind_primary_zone_file_content)
  }))
}

resource "azurerm_virtual_machine_run_command" "nva_apply_config" {
  name               = "apply-nva-configuration" # Or any descriptive name
  virtual_machine_id = azurerm_linux_virtual_machine.nva.id
  location           = azurerm_linux_virtual_machine.nva.location # Use VM's location

  # The script will be run as root
  run_as_user = "root"

  source {
    script = templatefile("${path.module}/apply_nva_config.sh", local.template_vars)
  }

  # This lifecycle block ensures the run command is re-triggered if the content of the template file changes.
  lifecycle {
    replace_triggered_by = [
      terraform_data.nva_config_trigger,
      # We also want to ensure this runs *after* the files are provisioned by the null_resources
      # particularly if any of the null_resources are replaced.
      null_resource.provision_bind_options,
      null_resource.provision_bind_local,
      null_resource.provision_bind_primary_zone,
    ]
  }
  depends_on = [
    null_resource.provision_bind_options,
    null_resource.provision_bind_local,
    null_resource.provision_bind_primary_zone,
  ]
  # If your script needs parameters that are sensitive:
  # protected_parameters = {
  #   "some_secret" = var.my_secret_value
  # }
  # And the script would access it via: echo $some_secret
  # However, for your current setup, embedding via templatefile is fine for non-secrets.
  # wg_server_private_key and wg_peer_public_key are sensitive.
  # The templatefile approach bakes them into the script content.
  # Run Command has `protected_parameters` but `source { script = ... }` is not inherently protected in tfstate if output.
  # Consider how these secrets are managed. If Key Vault, their values are resolved by Terraform apply.
  # For truly sensitive values passed to the script at runtime, use protected_parameters and have the script expect them as env vars.
  # Given your current setup directly embeds them, templatefile maintains that pattern.
}