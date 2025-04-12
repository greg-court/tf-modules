variable "name" {
  type        = string
  description = "Resource group name"
}

variable "keyvaults" {
  type        = map(map(string))
  description = "Map of key vault names to their configurations"
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