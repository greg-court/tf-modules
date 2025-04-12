output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "resource_group_id" {
  value = azurerm_resource_group.this.id
}

output "keyvaults" {
  value = {
    for kv in azurerm_key_vault.this : kv.name => kv.vault_uri
  }
}