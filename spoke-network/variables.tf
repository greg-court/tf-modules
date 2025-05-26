# Description: Variables for the Spoke Network Module

variable "location" {
  description = "The Azure region where resources will be created."
  type        = string
}

variable "location_short" {
  description = "Short location code (e.g., 'uks') used for peering names."
  type        = string
}

variable "resource_groups" {
  description = "A map of resource groups to create. Key is logical name, value contains configuration."
  type = map(object({
    name = string
    tags = optional(map(string), {})
  }))
  default = {}
}

# modules/spoke-network/variables.tf
variable "network_security_groups" {
  description = "..."
  type = map(object({
    name               = string
    resource_group_key = string
    security_rules = optional(list(object({
      name      = string
      priority  = number
      direction = string
      access    = string
      protocol  = string

      source_port_range       = optional(string)
      source_port_ranges      = optional(list(string))
      destination_port_range  = optional(string)
      destination_port_ranges = optional(list(string))

      source_address_prefix        = optional(string)
      source_address_prefixes      = optional(list(string))
      destination_address_prefix   = optional(string)
      destination_address_prefixes = optional(list(string))

      description                                = optional(string)
      source_application_security_group_ids      = optional(list(string))
      destination_application_security_group_ids = optional(list(string))
    })), [])
    tags = optional(map(string), {})
  }))
}

variable "route_tables" {
  description = "A map of Route Tables to create. Key is logical name (e.g., 'std_01'), value contains configuration."
  type = map(object({
    name                          = string
    resource_group_key            = string
    bgp_route_propagation_enabled = optional(bool, false) # Note: Provider argument is disable_bgp_route_propagation
    routes = optional(list(object({
      name                   = string
      address_prefix         = string
      next_hop_type          = string
      next_hop_in_ip_address = optional(string)
    })), [])
    tags = optional(map(string), {})
  }))
  default = {}
}

variable "common_routes" {
  description = "A list of common routes to add to ALL route tables created by this module instance."
  type        = list(any)
  default     = []
}

variable "virtual_networks" {
  description = "A map of Virtual Networks to create. Key is logical name (e.g., 'vnet_01'), value contains configuration including its subnets."
  type = map(object({
    name               = string
    resource_group_key = string
    address_space      = list(string)
    dns_servers        = optional(list(string), [])
    subnets = map(object({ # Subnet definitions remain here for input structure convenience
      name                       = string
      address_prefixes           = list(string)
      network_security_group_key = optional(string, null) # Logical key to var.network_security_groups
      route_table_key            = optional(string, null) # Logical key to var.route_tables
      delegation = optional(list(object({
        name = string
        service_delegation = object({
          name    = string
          actions = optional(list(string)) # Optional actions based on documentation
        })
      })), [])
      service_endpoints = optional(list(string), [])
      # Use string "Enabled" or "Disabled" as before for consistency with inline block. Will be converted to bool for azurerm_subnet.
      private_endpoint_network_policies             = optional(string, "Enabled")
      private_link_service_network_policies_enabled = optional(string, "Enabled")
    }))
    peer_to_hub = optional(bool, true)
    peer_to_hub_settings = optional(object({
      allow_forwarded_traffic              = optional(bool, true)
      allow_gateway_transit                = optional(bool, false)
      use_remote_gateways                  = optional(bool, false)
      create_reverse_peering               = optional(bool, true)
      reverse_allow_forwarded_traffic      = optional(bool, false)
      reverse_allow_gateway_transit        = optional(bool, true)
      reverse_allow_virtual_network_access = optional(bool, true)
      reverse_use_remote_gateways          = optional(bool, false)
    }), {})
    tags                    = optional(map(string), {})
    ddos_protection_plan_id = optional(string, null)
    enable_ddos_protection  = optional(bool, false) # Needs ddos_protection_plan block if true
    flow_timeout_in_minutes = optional(number, null)
  }))
  default = {}
}

variable "hub_vnet_id" {
  description = "The resource ID of the central Hub Virtual Network for peering."
  type        = string
}

variable "hub_resource_group_name" {
  description = "The name of the resource group containing the Hub VNet."
  type        = string
}

variable "autoregistration_private_dns_zone_name" {
  description = "The name of the Private DNS Zone in the connectivity subscription."
  type        = string
  default     = null
}

variable "autoregistration_private_dns_zone_resource_group_name" {
  description = "The name of the resource group containing the Private DNS Zone."
  type        = string
  default     = null
}

variable "common_tags" {
  description = "Default tags inherited from the root module."
  type        = map(string)
  default     = {}
}