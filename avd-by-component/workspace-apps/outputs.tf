output "workspace_id" {
  description = "The ID of the created AVD Workspace."
  value       = azurerm_virtual_desktop_workspace.workspace.id
}

output "workspace_name" {
  description = "The name of the created AVD Workspace."
  value       = azurerm_virtual_desktop_workspace.workspace.name
}

output "application_group_ids" {
  description = "A map of application group names to their IDs."
  value       = { for k, v in azurerm_virtual_desktop_application_group.app_groups : k => v.id }
}

output "application_group_names" {
  description = "A map of application group logical keys to their names."
  value       = { for k, v in azurerm_virtual_desktop_application_group.app_groups : k => v.name }
}