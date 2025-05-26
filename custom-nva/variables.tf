#################### filename: custom-nva/variables.tf ####################

variable "vm_name" {
  description = "Name of the Virtual Machine."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Resource Group to deploy the VM into."
  type        = string
}

variable "location" {
  description = "Azure region where the VM will be deployed."
  type        = string
}

variable "untrust_subnet_id" {
  description = "ID of the untrust subnet for the first NIC."
  type        = string
}

variable "trust_subnet_id" {
  description = "ID of the trust subnet for the second NIC."
  type        = string
}

variable "admin_username" {
  description = "Admin username for the VM."
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Admin password for the VM. Used if SSH key is not provided or if password auth is not disabled."
  type        = string
  sensitive   = true
  default     = null
}

variable "admin_ssh_public_key" {
  description = "Admin SSH public key for the VM. Recommended for security."
  type        = string
  default     = null
}

variable "vm_size" {
  description = "Size of the Virtual Machine."
  type        = string
  default     = "Standard_B1s"
}

variable "tags" {
  description = "A map of tags to assign to the resources."
  type        = map(string)
  default     = {}
}

# WireGuard Specific Variables
variable "wg_server_private_key" {
  description = "WireGuard server private key. Store securely (e.g., Azure Key Vault)."
  type        = string
  sensitive   = true
}

variable "wg_server_address_cidr" {
  description = "WireGuard server interface address with CIDR (e.g., X.X.X.X/24)."
  type        = string
}

variable "wg_listen_port" {
  description = "WireGuard listening port."
  type        = string # Keep as string as it's used in string interpolations
  default     = "6969"
}

variable "wg_peer_public_key" {
  description = "Public key of the WireGuard peer (on-premises endpoint)."
  type        = string
  sensitive   = true
}

variable "wg_peer_allowed_ips_cidr" {
  description = "The specific IP address (with /32 CIDR) assigned to the on-prem WireGuard peer within the WireGuard tunnel network (e.g., X.X.X.X/32). This is the peer's tunnel interface IP."
  type        = string
}

variable "untrust_interface_name" {
  description = "Name of the primary (untrust) network interface in the OS."
  type        = string
  default     = "eth0"
}

variable "trust_interface_name" {
  description = "Name of the secondary (trust) network interface in the OS."
  type        = string
  default     = "eth1"
}

variable "routing_ranges_onprem" {
  description = "List of on-premises IP CIDR ranges involved in NVA routing (e.g., [\"192.168.7.0/24\"])."
  type        = list(string)
  default     = []
}

variable "routing_ranges_azure" {
  description = "List of Azure IP CIDR ranges involved in NVA routing (e.g., [\"10.100.0.0/22\"] or specific spoke CIDRs). This will be used to add OS routes on the NVA pointing to the trust interface and for firewall rules."
  type        = list(string)
  default     = []
}

variable "on_prem_source_ip" {
  description = "The public IP address from which SSH to the NVA's untrust interface is allowed."
  type        = string
}

################### BIND DNS Server Configuration Variables ###################

variable "enable_bind_server" {
  description = "Flag to enable BIND DNS server configuration on the NVA."
  type        = bool
  default     = true
}

variable "bind_named_conf_options_content" {
  description = "Content for the /etc/bind/named.conf.options file."
  type        = string
  default     = ""
  sensitive   = true
}

variable "bind_named_conf_local_content" {
  description = "Content for the /etc/bind/named.conf.local file."
  type        = string
  default     = ""
  sensitive   = true
}

variable "bind_primary_zone_file_content" {
  description = "Content for the primary BIND zone file (e.g., db.yourdomain.local)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "bind_primary_zone_file_path" {
  description = "The full path on the NVA where the primary zone file should be placed (e.g., /etc/bind/zones/db.yourdomain.local). This path must match what's in named.conf.local."
  type        = string
  default     = "/etc/bind/db.primary" # A generic default
}

variable "untrust_nsg_id" {
  description = "ID of the Network Security Group (NSG) associated with the untrust interface."
  type        = string
}