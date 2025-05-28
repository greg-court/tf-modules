resource "azurerm_virtual_desktop_workspace" "workspace" {
  name                = var.workspace_config.name
  location            = var.location
  resource_group_name = var.resource_group_name
  friendly_name       = var.workspace_config.friendly_name
  description         = var.workspace_config.description
  tags                = var.tags
}

resource "azurerm_virtual_desktop_application_group" "app_groups" {
  for_each = { for ag_key, ag_val in var.application_groups_map : ag_key => ag_val }

  name                         = each.value.name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  type                         = each.value.type
  host_pool_id                 = each.value.host_pool_id
  friendly_name                = each.value.friendly_name
  description                  = each.value.description
  default_desktop_display_name = try(each.value.default_desktop_display_name, null)
  tags                         = var.tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "association" {
  for_each = azurerm_virtual_desktop_application_group.app_groups

  workspace_id         = azurerm_virtual_desktop_workspace.workspace.id
  application_group_id = each.value.id
}