############################## MANDATORY VARIABLES #############################

variable "subnet_id" {
  description = "The ID of the subnet where the VM will be deployed"
  type        = string
}

variable "os_type" {
  description = "The OS type for the VM. Can be 'linux' or 'windows'"
  type        = string

  validation {
    condition     = contains(["linux", "windows"], lower(var.os_type))
    error_message = "The os_type value must be either 'linux' or 'windows'."
  }
}

############################## OPTIONAL VARIABLES ##############################

# General Configuration
variable "use_existing_rg" {
  description = "Whether to deploy the VM into an existing resource group. If true, rg_name must be specified."
  type        = bool
  default     = false
}

variable "rg_name" {
  description = "Resource group name - can be either an existing RG name (when use_existing_rg is true) or a new RG name (when use_existing_rg is false). If not provided for a new RG, a name will be generated based on the VM name."
  type        = string
  default     = null
}

# VM Configuration
variable "vm_name" {
  description = "Custom name for the VM. If provided, this will override the automatically generated name."
  type        = string
  default     = null
}

variable "vm_name_prefix" {
  description = "Prefix for the VM name"
  type        = string
  default     = "vm-tshoot"
}

variable "vm_size" {
  description = "The size of the VM. Defaults to Standard_B1s for Linux and Standard_B2ms for Windows if not specified"
  type        = string
  default     = ""
}

variable "admin_username" {
  description = "The administrator username for the VM"
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "The administrator password for the VM"
  type        = string
  sensitive   = true
  default     = "P@$$w0rd123!"
}

variable "zone" {
  description = "The availability zone number for the VM. Valid values are 1, 2, 3"
  type        = number
  default     = null

  validation {
    condition     = var.zone == null ? true : contains([1, 2, 3], var.zone)
    error_message = "The zone value must be either null, 1, 2, or 3."
  }
}

# OS Disk Configuration
variable "os_disk_caching" {
  description = "The type of caching to use on the OS disk"
  type        = string
  default     = "ReadWrite"
}

variable "os_disk_storage_account_type" {
  description = "The storage account type for the OS disk"
  type        = string
  default     = "StandardSSD_LRS"
}

# Source Image Configuration
variable "source_image_publisher" {
  description = "The publisher of the VM image"
  type        = string
  default     = null
}

variable "source_image_offer" {
  description = "The offer of the VM image"
  type        = string
  default     = null
}

variable "source_image_sku" {
  description = "The SKU of the VM image"
  type        = string
  default     = null
}

variable "source_image_version" {
  description = "The version of the VM image"
  type        = string
  default     = "latest"
}

# Network Configuration
variable "private_ip_address_allocation" {
  description = "The private IP address allocation method"
  type        = string
  default     = "Dynamic"
}

# Security and Patching
variable "patch_mode" {
  description = "The patching mode for the VM"
  type        = string
  default     = "AutomaticByPlatform"
}

variable "bypass_platform_safety_checks" {
  description = "Enable bypass platform safety checks on user schedule"
  type        = bool
  default     = true
}

variable "secure_boot_enabled" {
  description = "Enable secure boot"
  type        = bool
  default     = false
}

# Tags
variable "vm_tags" {
  description = "A map of tags to assign to the virtual machine"
  type        = map(string)
  default     = {}
}

variable "rg_tags" {
  description = "A map of tags to assign to the resource group"
  type        = map(string)
  default     = {}
}

variable "private_ip_address" {
  description = "The static private IP address to assign to the VM when private_ip_address_allocation is set to 'Static'"
  type        = string
  default     = null
}

# Linux specific configuration
variable "enable_cloud_init" {
  description = "Enable installation of packages on first boot (Linux only)"
  type        = bool
  default     = true
}

variable "custom_cloud_init" {
  description = "Custom cloud-init config for Linux VMs. This completely replaces the default config when provided"
  type        = string
  default     = null
}