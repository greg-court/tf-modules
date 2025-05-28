output "host_pool_id" {
  description = "The ID of the created AVD Host Pool."
  value       = azurerm_virtual_desktop_host_pool.host_pool.id
}

output "host_pool_name" {
  description = "The name of the created AVD Host Pool."
  value       = azurerm_virtual_desktop_host_pool.host_pool.name
}

output "storage_account_id" {
  description = "The ID of the created Storage Account."
  value       = azurerm_storage_account.storage.id
}

output "storage_account_name" {
  description = "The name of the created Storage Account."
  value       = azurerm_storage_account.storage.name
}

output "session_host_ids" {
  description = "A map of session host names to their IDs."
  value       = { for k, v in azurerm_windows_virtual_machine.session_hosts : k => v.id }
}

output "scaling_plan_id" {
  description = "The ID of the AVD Scaling Plan, if created."
  value       = one(azurerm_virtual_desktop_scaling_plan.scaling_plan[*].id) # Using one() is correct as count is 0 or 1
}

output "host_pool_registration_token" {
  description = "The registration token for the host pool. Sensitive."
  value       = azurerm_virtual_desktop_host_pool_registration_info.host_pool_registration.token
  sensitive   = true
}