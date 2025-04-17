output "rg_name" {
  description = "The name of the resource group"
  value       = local.resource_group_name
}

output "vm_id" {
  description = "The ID of the VM"
  value       = lower(var.os_type) == "linux" ? azurerm_linux_virtual_machine.this[0].id : azurerm_windows_virtual_machine.this[0].id
}

output "vm_name" {
  description = "The name of the VM"
  value       = local.vm_name
}

output "private_ip_address" {
  description = "The private IP address of the VM"
  value       = lower(var.os_type) == "linux" ? azurerm_linux_virtual_machine.this[0].private_ip_address : azurerm_windows_virtual_machine.this[0].private_ip_address
}

output "admin_username" {
  description = "The administrator username for the VM"
  value       = var.admin_username
}

output "admin_password" {
  description = "The administrator password for the VM"
  value       = var.admin_password
  sensitive   = true
}