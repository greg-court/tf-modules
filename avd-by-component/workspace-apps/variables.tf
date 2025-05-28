variable "location" {
  description = "The Azure region where workspace and application group resources will be deployed."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the Azure Resource Group where workspace and application groups will be deployed."
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resources."
  type        = map(string)
  default     = {}
}

variable "workspace_config" {
  description = "Configuration for the AVD Workspace."
  type = object({
    name          = string
    friendly_name = string
    description   = optional(string)
  })
}

variable "application_groups_map" {
  description = "A map of configurations for AVD Application Groups. The key of the map can be a logical name for the app group."
  type = map(object({
    name                          = string
    type                          = string # "Desktop" or "RemoteApp"
    host_pool_id                  = string
    friendly_name                 = string
    description                   = optional(string)
    default_desktop_display_name  = optional(string) # Only for "Desktop" type
    # For RemoteApp, you'd add app definitions here if creating from scratch, or associate existing apps.
    # For simplicity, this example focuses on Desktop type matching your current setup.
  }))
}