variable "rg_name" {
  type        = string
  description = "Resource group name"
}

variable "rg_tags" {
  type        = map(string)
  description = "Optional tags to assign specifically to the resource group."
  default     = {}
}

variable "keyvaults" {
  type        = map(any)
  description = "Map of key vault names to their configurations. Each configuration map can optionally include a 'tags' key with a map(string) value for key vault specific tags."
  default     = {}
}

variable "tenant_id" {
  type = string
}

variable "location" {
  type = string
}

variable "sku_name" {
  type    = string
  default = "standard"
}

variable "enable_rbac_authorization" {
  type    = bool
  default = true
}

variable "soft_delete_retention_days" {
  type    = number
  default = 7
}