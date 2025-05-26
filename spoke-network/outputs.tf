output "resource_group_ids" {
  description = "Map of resource group IDs, keyed by the logical name."
  value = {
    for rg_key, rg in azurerm_resource_group.this : rg_key => rg.id
  }
}

output "network_security_group_ids" {
  description = "Map of NSG IDs, keyed by the logical name."
  value = {
    for nsg_key, nsg in azurerm_network_security_group.this : nsg_key => nsg.id
  }
}

output "route_table_ids" {
  description = "Map of route table IDs, keyed by the logical name."
  value = {
    for rt_key, rt in azurerm_route_table.this : rt_key => rt.id
  }
}

output "virtual_network_ids" {
  description = "Map of virtual network IDs, keyed by the logical name."
  value = {
    for vnet_key, vnet in azurerm_virtual_network.this : vnet_key => vnet.id
  }
}

output "virtual_network_names" {
  description = "Map of virtual network names, keyed by the logical name."
  value = {
    for vnet_key, vnet in azurerm_virtual_network.this : vnet_key => vnet.name
  }
}

output "subnet_ids" {
  description = "Map of subnet IDs, keyed by the flattened logical name ('vnet_key.subnet_key')."
  value = {
    for subnet_key, subnet_azapi in azapi_resource.subnet : subnet_key => subnet_azapi.id
  }
}

output "subnet_names" {
  description = "Map of subnet names, keyed by the flattened logical name ('vnet_key.subnet_key')."
  value = {
    for subnet_key, subnet_azapi in azapi_resource.subnet : subnet_key => subnet_azapi.name
  }
}

output "peering_spoke_to_hub_ids" {
  description = "Map of Spoke-to-Hub VNet peering IDs, keyed by VNet logical name."
  value = {
    for peering_key, peering in azurerm_virtual_network_peering.spoke_to_hub : peering_key => peering.id
  }
}

output "peering_hub_to_spoke_ids" {
  description = "Map of Hub-to-Spoke VNet peering IDs, keyed by VNet logical name."
  value = {
    for peering_key, peering in azurerm_virtual_network_peering.hub_to_spoke : peering_key => peering.id
  }
}