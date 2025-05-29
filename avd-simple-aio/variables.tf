variable "resource_group_name" {
  description = "The name of the Azure Resource Group where AVD resources will be deployed."
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed."
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resources."
  type        = map(string)
  default     = {}
}

variable "subscription_id" {
  description = "The Azure subscription ID where the AVD resources are deployed."
  type        = string
}

variable "host_pool_config" {
  description = "Configuration for the AVD Host Pool."
  type = object({
    name                  = string
    type                  = string
    max_sessions_allowed  = number
    load_balancer_type    = string
    friendly_name         = string
    description           = optional(string)
    custom_rdp_properties = optional(string)
  })
}

variable "workspace_config" {
  description = "Configuration for the AVD Workspace."
  type = object({
    name          = string
    friendly_name = string
    description   = optional(string)
  })
}

variable "application_groups_config" {
  description = "A list of configurations for AVD Application Groups."
  type = list(object({
    name                         = string
    type                         = string
    friendly_name                = string
    description                  = optional(string)
    default_desktop_display_name = optional(string)
    group_assignments            = optional(list(string), [])
  }))
}

variable "storage_account_config" {
  description = "Configuration for the Storage Account for FSLogix profiles."
  type = object({
    name                                     = string
    tier                                     = string
    replication_type                         = string
    private_endpoint_subnet_id               = optional(string)
    private_dns_zone_ids_file                = optional(list(string))
    network_rules_virtual_network_subnet_ids = optional(list(string), [])
    network_rules_default_action             = optional(string, "Deny")
    public_network_access_enabled            = optional(bool, false)
    default_to_oauth_authentication          = optional(bool, true)
  })
}

variable "file_shares_config" {
  description = "A list of configurations for file shares within the storage account."
  type = list(object({
    name     = string
    protocol = string
    quota    = number
  }))
}

variable "subnet_id" {
  description = "The ID of the subnet where session host NICs will be deployed."
  type        = string
}

variable "active_directory_domain" {
  description = "The Active Directory domain name for domain joining session hosts."
  type        = string
}

variable "domain_join_username" {
  description = "The username for domain joining session hosts."
  type        = string
}

variable "avd_domain_join_password" {
  description = "The password for the domain join user account."
  type        = string
  sensitive   = true
}

variable "admin_username" {
  description = "The administrator username for the session host VMs."
  type        = string
}

variable "avd_host_admin_password" {
  description = "The administrator password for the session host VMs."
  type        = string
  sensitive   = true
}

variable "session_hosts_config" {
  description = "A map of configurations for groups of AVD Session Hosts."
  type = map(object({
    vm_name_prefix        = string
    vm_size               = string
    instances             = list(string)
    ou_path               = string
    zones                 = optional(list(string), ["1", "2", "3"])
    patch_assessment_mode = optional(string, "AutomaticByPlatform")
    storage_account_type  = optional(string, "StandardSSD_LRS")
    priority              = optional(string, "Regular")
    eviction_policy       = optional(string, "Deallocate")
    disk_size_gb          = optional(number)
    secure_boot_enabled   = optional(bool, true)
    image_config = object({
      type             = string
      gallery_image_id = optional(string)
      marketplace_image = optional(object({
        publisher = string
        offer     = string
        sku       = string
        version   = string
      }))
    })
  }))
}

variable "scaling_plan_config" {
  description = "Configuration for the AVD Scaling Plan. Set to null to disable scaling plan creation."
  type = object({
    name                  = string
    friendly_name         = string
    description           = string
    time_zone             = string
    assign_autoscale_role = optional(bool, true)
    host_pool_associations = list(object({
      scaling_plan_enabled = bool
    }))
    schedules = list(object({
      name                                 = string
      days_of_week                         = list(string)
      ramp_up_start_time                   = string
      ramp_up_load_balancing_algorithm     = string
      ramp_up_minimum_hosts_percent        = number
      ramp_up_capacity_threshold_percent   = number
      peak_start_time                      = string
      peak_load_balancing_algorithm        = string
      ramp_down_start_time                 = string
      ramp_down_load_balancing_algorithm   = string
      ramp_down_minimum_hosts_percent      = number
      ramp_down_capacity_threshold_percent = number
      ramp_down_force_logoff_users         = bool
      ramp_down_wait_time_minutes          = number
      ramp_down_notification_message       = string
      ramp_down_stop_hosts_when            = string
      off_peak_start_time                  = string
      off_peak_load_balancing_algorithm    = string
    }))
  })
  default = null
}