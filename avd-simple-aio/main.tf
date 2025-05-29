resource "azurerm_virtual_desktop_host_pool" "host_pool" {
  name                     = var.host_pool_config.name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  type                     = var.host_pool_config.type
  maximum_sessions_allowed = var.host_pool_config.max_sessions_allowed
  load_balancer_type       = var.host_pool_config.load_balancer_type
  friendly_name            = var.host_pool_config.friendly_name
  description              = var.host_pool_config.description
  custom_rdp_properties    = var.host_pool_config.custom_rdp_properties
  validate_environment     = true
  tags                     = var.tags

  lifecycle {
    ignore_changes = [
      vm_template
    ]
  }
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "host_pool_registration" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.host_pool.id
  expiration_date = timeadd(timestamp(), "24h")
}

resource "azurerm_virtual_desktop_workspace" "workspace" {
  name                = var.workspace_config.name
  location            = var.location
  resource_group_name = var.resource_group_name
  friendly_name       = var.workspace_config.friendly_name
  description         = var.workspace_config.description
  tags                = var.tags
}

resource "azurerm_virtual_desktop_application_group" "app_groups" {
  for_each = { for ag in var.application_groups_config : ag.name => ag }

  name                         = each.value.name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  type                         = each.value.type
  host_pool_id                 = azurerm_virtual_desktop_host_pool.host_pool.id
  friendly_name                = each.value.friendly_name
  description                  = each.value.description
  default_desktop_display_name = each.value.default_desktop_display_name
  tags                         = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "association" {
  for_each = azurerm_virtual_desktop_application_group.app_groups

  workspace_id         = azurerm_virtual_desktop_workspace.workspace.id
  application_group_id = each.value.id
}

locals {
  app_group_role_assignments_flat = flatten([
    for ag_config in var.application_groups_config : [
      for group_name_str in ag_config.group_assignments : {
        assignment_key         = "${ag_config.name}_${replace(group_name_str, "/[^a-zA-Z0-9-_]/", "_")}"
        app_group_resource_key = ag_config.name
        group_name_to_assign   = group_name_str
      }
    ]
  ])

  app_group_assignments_for_each = {
    for assignment in local.app_group_role_assignments_flat : assignment.assignment_key => assignment
  }

  all_vms = {
    for vm_config_key, vm_config_val in var.session_hosts_config :
    vm_config_key => {
      for idx, inst_suffix in vm_config_val.instances :
      "${vm_config_key}-${inst_suffix}" => {
        vm_group_key            = vm_config_key
        host_pool_name          = azurerm_virtual_desktop_host_pool.host_pool.name
        resource_group_name     = var.resource_group_name
        subnet_id               = var.subnet_id
        vm_size                 = vm_config_val.vm_size
        vm_name_prefix          = vm_config_val.vm_name_prefix
        ou_path                 = vm_config_val.ou_path
        registration_token_info = azurerm_virtual_desktop_host_pool_registration_info.host_pool_registration.token
        vm_name                 = "${vm_config_val.vm_name_prefix}${inst_suffix}"
        nic_name                = "${vm_config_val.vm_name_prefix}${inst_suffix}-nic"


        zone                  = length(vm_config_val.zones) > 0 ? vm_config_val.zones[idx % length(vm_config_val.zones)] : null
        patch_assessment_mode = vm_config_val.patch_assessment_mode
        storage_account_type  = vm_config_val.storage_account_type
        priority              = vm_config_val.priority

        eviction_policy     = (vm_config_val.priority == "Spot") ? vm_config_val.eviction_policy : null
        disk_size_gb        = vm_config_val.disk_size_gb
        image_type          = vm_config_val.image_config.type
        gallery_image_id    = vm_config_val.image_config.gallery_image_id
        marketplace_image   = vm_config_val.image_config.marketplace_image
        secure_boot_enabled = vm_config_val.secure_boot_enabled
      }
    }
  }
  flattened_vms                 = merge(values(local.all_vms)...)
  create_autoscale_dependencies = var.scaling_plan_config != null ? var.scaling_plan_config.assign_autoscale_role : false
}

data "azuread_group" "assigned_avd_user_group" {
  for_each     = local.app_group_assignments_for_each
  display_name = each.value.group_name_to_assign
}

resource "azurerm_role_assignment" "app_group_user_assignments" {
  for_each             = local.app_group_assignments_for_each
  scope                = azurerm_virtual_desktop_application_group.app_groups[each.value.app_group_resource_key].id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = data.azuread_group.assigned_avd_user_group[each.key].object_id

  depends_on = [
    azurerm_virtual_desktop_application_group.app_groups
  ]
}

resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_config.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = var.storage_account_config.tier
  account_replication_type = var.storage_account_config.replication_type
  account_kind             = "StorageV2"

  public_network_access_enabled   = var.storage_account_config.public_network_access_enabled
  default_to_oauth_authentication = var.storage_account_config.default_to_oauth_authentication

  network_rules {
    default_action             = var.storage_account_config.network_rules_default_action
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = var.storage_account_config.network_rules_virtual_network_subnet_ids
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      azure_files_authentication
    ]
  }
}

resource "azurerm_storage_share" "file_shares" {
  for_each = { for fs in var.file_shares_config : fs.name => fs }

  name               = each.value.name
  storage_account_id = azurerm_storage_account.storage.id
  enabled_protocol   = each.value.protocol
  quota              = each.value.quota
}

resource "azurerm_private_endpoint" "storage_file_pe" {
  count = var.storage_account_config.private_endpoint_subnet_id != null && var.storage_account_config.private_dns_zone_ids_file != null && length(var.storage_account_config.private_dns_zone_ids_file) > 0 ? 1 : 0

  name                = "${var.storage_account_config.name}-file-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.storage_account_config.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.storage_account_config.name}-psc-file"
    private_connection_resource_id = azurerm_storage_account.storage.id
    is_manual_connection           = false
    subresource_names              = ["file"]
  }

  private_dns_zone_group {
    name                 = "file-privatednszonegroup"
    private_dns_zone_ids = var.storage_account_config.private_dns_zone_ids_file
  }
  depends_on = [azurerm_storage_account.storage]
}

resource "azurerm_network_interface" "vm_nics" {
  for_each = local.flattened_vms

  name                = each.value.nic_name
  location            = var.location
  resource_group_name = each.value.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "session_hosts" {
  for_each = local.flattened_vms

  name                  = each.value.vm_name
  location              = var.location
  resource_group_name   = each.value.resource_group_name
  size                  = each.value.vm_size
  network_interface_ids = [azurerm_network_interface.vm_nics[each.key].id]
  admin_username        = var.admin_username
  admin_password        = var.avd_host_admin_password
  patch_assessment_mode = each.value.patch_assessment_mode

  secure_boot_enabled        = each.value.secure_boot_enabled
  vtpm_enabled               = true
  encryption_at_host_enabled = false

  source_image_id = each.value.image_type == "gallery" && each.value.gallery_image_id != null ? each.value.gallery_image_id : null

  dynamic "source_image_reference" {
    for_each = each.value.image_type == "marketplace" && each.value.marketplace_image != null ? [each.value.marketplace_image] : []
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  zone            = each.value.zone
  priority        = each.value.priority
  eviction_policy = each.value.eviction_policy

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = each.value.storage_account_type
    disk_size_gb         = each.value.disk_size_gb
  }

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {}
  tags = var.tags

  depends_on = [
    azurerm_virtual_desktop_host_pool_registration_info.host_pool_registration
  ]

  lifecycle {
    ignore_changes = [
      vm_agent_platform_updates_enabled,
      admin_password,
      patch_assessment_mode,
      tags
    ]
  }
}

resource "azurerm_virtual_machine_extension" "domain_join" {
  for_each = local.flattened_vms

  name                       = "domainJoin-${each.key}"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_hosts[each.key].id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  settings = jsonencode({
    Name    = var.active_directory_domain
    OUPath  = each.value.ou_path
    User    = var.domain_join_username
    Restart = "true"
    Options = "3"
  })

  protected_settings = jsonencode({
    Password = var.avd_domain_join_password
  })

  depends_on = [azurerm_windows_virtual_machine.session_hosts]
  lifecycle {
    ignore_changes = [
      protected_settings,
      tags
    ]
  }
}

resource "azurerm_virtual_machine_extension" "session_host_registration" {
  for_each = local.flattened_vms

  name                       = "avdDsc-${each.key}"
  virtual_machine_id         = azurerm_windows_virtual_machine.session_hosts[each.key].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  settings = jsonencode({
    modulesUrl            = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_09-08-2022.zip"
    configurationFunction = "Configuration.ps1\\AddSessionHost"
    properties = {
      HostPoolName = each.value.host_pool_name
    }
  })

  protected_settings = jsonencode({
    properties = {
      registrationInfoToken = each.value.registration_token_info
    }
  })

  depends_on = [
    azurerm_virtual_machine_extension.domain_join,
    azurerm_virtual_desktop_host_pool.host_pool
  ]

  lifecycle {
    ignore_changes = [
      protected_settings,
      tags
    ]
  }
}

resource "azurerm_virtual_desktop_scaling_plan" "scaling_plan" {
  count = local.create_autoscale_dependencies ? 1 : 0

  name                = var.scaling_plan_config.name
  location            = var.location
  resource_group_name = var.resource_group_name
  friendly_name       = var.scaling_plan_config.friendly_name
  time_zone           = var.scaling_plan_config.time_zone
  description         = var.scaling_plan_config.description
  tags                = var.tags

  dynamic "host_pool" {
    for_each = var.scaling_plan_config.host_pool_associations
    content {
      hostpool_id          = azurerm_virtual_desktop_host_pool.host_pool.id
      scaling_plan_enabled = host_pool.value.scaling_plan_enabled
    }
  }

  dynamic "schedule" {
    for_each = var.scaling_plan_config.schedules
    content {
      name                                 = schedule.value.name
      days_of_week                         = schedule.value.days_of_week
      ramp_up_start_time                   = schedule.value.ramp_up_start_time
      ramp_up_load_balancing_algorithm     = schedule.value.ramp_up_load_balancing_algorithm
      ramp_up_minimum_hosts_percent        = schedule.value.ramp_up_minimum_hosts_percent
      ramp_up_capacity_threshold_percent   = schedule.value.ramp_up_capacity_threshold_percent
      peak_start_time                      = schedule.value.peak_start_time
      peak_load_balancing_algorithm        = schedule.value.peak_load_balancing_algorithm
      ramp_down_start_time                 = schedule.value.ramp_down_start_time
      ramp_down_load_balancing_algorithm   = schedule.value.ramp_down_load_balancing_algorithm
      ramp_down_minimum_hosts_percent      = schedule.value.ramp_down_minimum_hosts_percent
      ramp_down_capacity_threshold_percent = schedule.value.ramp_down_capacity_threshold_percent
      ramp_down_force_logoff_users         = schedule.value.ramp_down_force_logoff_users
      ramp_down_wait_time_minutes          = schedule.value.ramp_down_wait_time_minutes
      ramp_down_notification_message       = schedule.value.ramp_down_notification_message
      ramp_down_stop_hosts_when            = schedule.value.ramp_down_stop_hosts_when
      off_peak_start_time                  = schedule.value.off_peak_start_time
      off_peak_load_balancing_algorithm    = schedule.value.off_peak_load_balancing_algorithm
    }
  }
  depends_on = [azurerm_role_assignment.avd_autoscale_assignment]
}

data "azuread_service_principal" "avd_sp" {
  count        = local.create_autoscale_dependencies ? 1 : 0
  display_name = "Azure Virtual Desktop"
}

resource "azurerm_role_assignment" "avd_autoscale_assignment" {
  count = local.create_autoscale_dependencies ? 1 : 0

  scope                            = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name             = "Desktop Virtualization Power On Off Contributor"
  principal_id                     = data.azuread_service_principal.avd_sp[0].object_id
  skip_service_principal_aad_check = true
}