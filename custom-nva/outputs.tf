output "vm_id" {
  description = "The ID of the NVA Virtual Machine."
  value       = azurerm_linux_virtual_machine.nva.id
}

output "untrust_nic_id" {
  description = "The ID of the untrust network interface."
  value       = azurerm_network_interface.untrust_nic.id
}

output "trust_nic_id" {
  description = "The ID of the trust network interface."
  value       = azurerm_network_interface.trust_nic.id
}

output "public_ip_address" {
  description = "The Public IP address of the NVA."
  value       = azurerm_public_ip.pip.ip_address
}