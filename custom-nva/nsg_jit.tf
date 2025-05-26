data "http" "devops_agent_ip" {
  url = "https://wtfismyip.com/text"
}

locals {
  untrust_nsg_id_parts            = split("/", var.untrust_nsg_id)
  untrust_nsg_resource_group_name = local.untrust_nsg_id_parts[4]
  untrust_nsg_name                = local.untrust_nsg_id_parts[8]
  devops_agent_ip                 = chomp(data.http.devops_agent_ip.response_body) # Ensure http data source is defined
  temp_nsg_rule_name_ssh_devops   = "TempAllowSSHFromDevOpsAgent"
  temp_nsg_rule_priority_ssh      = 101
  subscription_id_from_nsg_id     = local.untrust_nsg_id_parts[2]
}

# --- Step 1: Add the Temporary NSG Rule ---
resource "null_resource" "add_temp_ssh_rule" {
  # Triggers: Re-run if VM changes or BIND content changes, or agent IP changes
  triggers = {
    vm_id                          = azurerm_linux_virtual_machine.nva.id
    bind_options_content_sha1      = sha1(var.bind_named_conf_options_content)
    bind_local_content_sha1        = sha1(var.bind_named_conf_local_content)
    bind_primary_zone_content_sha1 = sha1(var.bind_primary_zone_file_content)
    devops_agent_ip_trigger        = local.devops_agent_ip # From main.tf locals
  }

  provisioner "local-exec" { # ADD THE NSG RULE
    command     = <<EOT
echo "Attempting to set subscription to ${local.subscription_id_from_nsg_id}..."
az account set --subscription "${local.subscription_id_from_nsg_id}" || { echo "ERROR: Failed to set Azure subscription ${local.subscription_id_from_nsg_id}"; exit 1; }

echo "Attempting to add NSG rule ${local.temp_nsg_rule_name_ssh_devops} for IP ${local.devops_agent_ip} in RG ${local.untrust_nsg_resource_group_name}..."
az network nsg rule create \
  --resource-group "${local.untrust_nsg_resource_group_name}" \
  --nsg-name "${local.untrust_nsg_name}" \
  --name "${local.temp_nsg_rule_name_ssh_devops}" \
  --priority ${local.temp_nsg_rule_priority_ssh} \
  --source-address-prefixes "${local.devops_agent_ip}" \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp \
  --description "Temp SSH for DevOps Agent (Terraform - Add)" || { echo "ERROR: Failed to create NSG rule"; exit 1; }
echo "NSG rule ${local.temp_nsg_rule_name_ssh_devops} add command reported."
EOT
    interpreter = ["bash", "-c"]
  }
  depends_on = [azurerm_linux_virtual_machine.nva] # Ensure VM (and its NSG/PIP) is available
}

# --- Step 3: Remove the Temporary NSG Rule ---
resource "null_resource" "remove_temp_ssh_rule" {
  # Triggers: This should run after files are provisioned.
  # Its replacement should be tied to the same conditions that required provisioning.
  triggers = {
    vm_id                          = azurerm_linux_virtual_machine.nva.id # Keep consistent
    bind_options_content_sha1      = sha1(var.bind_named_conf_options_content)
    bind_local_content_sha1        = sha1(var.bind_named_conf_local_content)
    bind_primary_zone_content_sha1 = sha1(var.bind_primary_zone_file_content)
    # Adding a trigger based on the add_rule resource ensures this runs if add_rule runs
    add_rule_done_trigger = null_resource.add_temp_ssh_rule.id
  }

  provisioner "local-exec" { # REMOVE THE NSG RULE
    command     = <<EOT
  echo "Attempting to set subscription to ${local.subscription_id_from_nsg_id} for delete operation..."
  az account set --subscription "${local.subscription_id_from_nsg_id}" || { echo "WARNING: Failed to set Azure subscription for delete. Rule might not be cleaned up if in wrong subscription context."; exit 0; } # Don't fail pipeline if sub set fails on destroy

echo "Attempting to remove NSG rule ${local.temp_nsg_rule_name_ssh_devops} from RG ${local.untrust_nsg_resource_group_name}..."
az network nsg rule delete \
  --resource-group "${local.untrust_nsg_resource_group_name}" \
  --nsg-name "${local.untrust_nsg_name}" \
  --name "${local.temp_nsg_rule_name_ssh_devops}" || echo "Rule ${local.temp_nsg_rule_name_ssh_devops} not found or delete failed. This might be okay."
echo "NSG rule ${local.temp_nsg_rule_name_ssh_devops} delete command reported."
EOT
    interpreter = ["bash", "-c"]
  }

  # This resource depends on all file provisioners completing
  depends_on = [
    null_resource.provision_bind_options,
    null_resource.provision_bind_local,
    null_resource.provision_bind_primary_zone,
  ]
}