resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
}

resource "azurerm_key_vault" "this" {
  for_each                   = var.keyvaults
  name                       = each.key
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  sku_name                   = lookup(each.value, "sku_name", var.sku_name)
  tenant_id                  = var.tenant_id
  enable_rbac_authorization  = lookup(each.value, "enable_rbac_authorization", var.enable_rbac_authorization)
  soft_delete_retention_days = lookup(each.value, "soft_delete_retention_days", var.soft_delete_retention_days)
}