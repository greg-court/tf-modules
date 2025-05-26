terraform {
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      configuration_aliases = [azurerm.connectivity]
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 1.12.0"
    }
  }
}

locals {
  # Merge common tags with specific resource tags
  merged_rg_tags   = { for k, rg in var.resource_groups : k => merge(var.common_tags, rg.tags) }
  merged_nsg_tags  = { for k, nsg in var.network_security_groups : k => merge(var.common_tags, try(nsg.tags, {})) }
  merged_rt_tags   = { for k, rt in var.route_tables : k => merge(var.common_tags, try(rt.tags, {})) }
  merged_vnet_tags = { for k, vnet in var.virtual_networks : k => merge(var.common_tags, try(vnet.tags, {})) }

  # Add common routes to each route table definition
  processed_route_tables = {
    for rt_key, rt_config in var.route_tables : rt_key => merge(rt_config, {
      routes = concat(var.common_routes, rt_config.routes)
    })
  }

  # Extract Hub VNet name from its ID
  hub_vnet_name = regex(".*virtualNetworks/(.*)", var.hub_vnet_id)[0]

  # Create a flattened map of subnets for easier iteration, including parent VNet info
  flattened_subnets = flatten([
    for vnet_key, vnet_config in var.virtual_networks : [
      for subnet_key, subnet_config in vnet_config.subnets : {
        flat_key             = "${vnet_key}.${subnet_key}"
        vnet_key             = vnet_key
        subnet_key           = subnet_key
        subnet_config        = subnet_config
        virtual_network_name = vnet_config.name
        resource_group_key   = vnet_config.resource_group_key
      }
    ]
  ])

  # Key the flattened subnets by their unique flat_key
  subnets_map = { for subnet in local.flattened_subnets : subnet.flat_key => subnet }
}

# --- Resource Groups ---
resource "azurerm_resource_group" "this" {
  for_each = var.resource_groups

  name     = each.value.name
  location = var.location
  tags     = local.merged_rg_tags[each.key]
}

# --- Network Security Groups ---
resource "azurerm_network_security_group" "this" {
  for_each = var.network_security_groups

  name                = each.value.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this[each.value.resource_group_key].name
  tags                = local.merged_nsg_tags[each.key]

  dynamic "security_rule" {
    for_each = each.value.security_rules
    iterator = rule
    content {
      name                                       = rule.value.name
      description                                = try(rule.value.description, null)
      priority                                   = rule.value.priority
      direction                                  = rule.value.direction
      access                                     = rule.value.access
      protocol                                   = rule.value.protocol
      source_port_range                          = try(rule.value.source_port_range, null)
      source_port_ranges                         = try(rule.value.source_port_ranges, [])
      destination_port_range                     = try(rule.value.destination_port_range, null)
      destination_port_ranges                    = try(rule.value.destination_port_ranges, [])
      source_address_prefix                      = try(rule.value.source_address_prefix, null)
      source_address_prefixes                    = try(rule.value.source_address_prefixes, [])
      source_application_security_group_ids      = try(rule.value.source_application_security_group_ids, [])
      destination_address_prefix                 = try(rule.value.destination_address_prefix, null)
      destination_address_prefixes               = try(rule.value.destination_address_prefixes, [])
      destination_application_security_group_ids = try(rule.value.destination_application_security_group_ids, [])
    }
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# --- Route Tables ---
resource "azurerm_route_table" "this" {
  for_each = local.processed_route_tables

  name                          = each.value.name
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this[each.value.resource_group_key].name
  bgp_route_propagation_enabled = each.value.bgp_route_propagation_enabled
  tags                          = local.merged_rt_tags[each.key]

  dynamic "route" {
    for_each = each.value.routes
    iterator = rt_route
    content {
      name                   = rt_route.value.name
      address_prefix         = rt_route.value.address_prefix
      next_hop_type          = rt_route.value.next_hop_type
      next_hop_in_ip_address = lookup(rt_route.value, "next_hop_in_ip_address", null)
    }
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# --- Virtual Networks (Subnets created via AzAPI below) ---
resource "azurerm_virtual_network" "this" {
  for_each = var.virtual_networks

  name                    = each.value.name
  location                = var.location
  resource_group_name     = azurerm_resource_group.this[each.value.resource_group_key].name
  address_space           = each.value.address_space
  dns_servers             = try(each.value.dns_servers, null)
  tags                    = local.merged_vnet_tags[each.key]
  flow_timeout_in_minutes = try(each.value.flow_timeout_in_minutes, null)

  dynamic "ddos_protection_plan" {
    for_each = each.value.ddos_protection_plan_id != null ? [1] : []
    content {
      id     = each.value.ddos_protection_plan_id
      enable = each.value.enable_ddos_protection
    }
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# --- Subnets (Defined via AzAPI Resource) ---
resource "azapi_resource" "subnet" {
  for_each = local.subnets_map

  type      = "Microsoft.Network/virtualNetworks/subnets@2023-11-01"
  name      = each.value.subnet_config.name
  parent_id = azurerm_virtual_network.this[each.value.vnet_key].id

  body = {
    properties = {
      addressPrefixes = each.value.subnet_config.address_prefixes
      # --- Network Security Group Association ---
      networkSecurityGroup = each.value.subnet_config.network_security_group_key != null ? {
        id = azurerm_network_security_group.this[each.value.subnet_config.network_security_group_key].id
      } : null
      # --- Route Table Association ---
      routeTable = each.value.subnet_config.route_table_key != null ? {
        id = azurerm_route_table.this[each.value.subnet_config.route_table_key].id
      } : null
      # --- Service Endpoints ---
      serviceEndpoints = try(each.value.subnet_config.service_endpoints, null) != null ? [
        for se in each.value.subnet_config.service_endpoints : { service = se }
      ] : null
      # --- Delegations ---
      delegations = try(each.value.subnet_config.delegation, null) != null ? [
        for del in each.value.subnet_config.delegation : {
          name = del.name
          properties = {
            serviceName = del.service_delegation.name
          }
        }
      ] : null
      # --- Network Policies ---
      privateEndpointNetworkPolicies    = try(each.value.subnet_config.private_endpoint_network_policies, "Enabled")
      privateLinkServiceNetworkPolicies = try(each.value.subnet_config.private_link_service_network_policies_enabled, "Enabled")
    }
  }

  locks = [azurerm_virtual_network.this[each.value.vnet_key].id]

  lifecycle {
    ignore_changes = [
      body.properties.ipConfigurations,
      body.properties.privateEndpoints
    ]
  }
}

# --- Spoke to Hub Peering ---
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each = { for k, v in var.virtual_networks : k => v if try(v.peer_to_hub, true) }

  name                         = format("peer-%s-to-hub-%s", trimsuffix(lower(each.value.name), "-01"), var.location_short)
  resource_group_name          = azurerm_resource_group.this[each.value.resource_group_key].name
  virtual_network_name         = azurerm_virtual_network.this[each.key].name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = each.value.peer_to_hub_settings.allow_forwarded_traffic
  allow_gateway_transit        = each.value.peer_to_hub_settings.allow_gateway_transit
  use_remote_gateways          = each.value.peer_to_hub_settings.use_remote_gateways
}

# --- Hub to Spoke Peering (Reverse) ---
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  provider = azurerm.connectivity

  for_each = { for k, v in var.virtual_networks : k => v if try(v.peer_to_hub, true) && try(v.peer_to_hub_settings.create_reverse_peering, true) }

  name                         = format("peer-hub-%s-to-%s", var.location_short, trimsuffix(lower(each.value.name), "-01"))
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = local.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.this[each.key].id
  allow_virtual_network_access = each.value.peer_to_hub_settings.reverse_allow_virtual_network_access
  allow_forwarded_traffic      = each.value.peer_to_hub_settings.reverse_allow_forwarded_traffic
  allow_gateway_transit        = each.value.peer_to_hub_settings.reverse_allow_gateway_transit
  use_remote_gateways          = each.value.peer_to_hub_settings.reverse_use_remote_gateways

  depends_on = [
    azurerm_virtual_network_peering.spoke_to_hub
  ]
}


# --- Private DNS Zone VNET Links ---
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  provider = azurerm.connectivity

  for_each = var.autoregistration_private_dns_zone_name != null && var.autoregistration_private_dns_zone_resource_group_name != null ? azurerm_virtual_network.this : {}

  name                  = substr(format("link-%s-to-%s", each.value.name, replace(var.autoregistration_private_dns_zone_name, ".", "-")), 0, 80)
  resource_group_name   = var.autoregistration_private_dns_zone_resource_group_name
  private_dns_zone_name = var.autoregistration_private_dns_zone_name
  virtual_network_id    = each.value.id
  registration_enabled  = true

  lifecycle {
    ignore_changes = [tags]
  }
}