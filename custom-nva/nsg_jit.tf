data "http" "devops_agent_ip" {
  url = "https://www.wtfismyip.com"
}
resource "null_resource" "manage_devops_ssh_rule" {
  # Triggers: Re-create this null_resource (and thus re-run its provisioners)
  # if the VM ID changes OR if any BIND file content changes (which means files need re-provisioning).
  triggers = {
    vm_id                          = azurerm_linux_virtual_machine.nva.id
    bind_options_content_sha1      = sha1(var.bind_named_conf_options_content)
    bind_local_content_sha1        = sha1(var.bind_named_conf_local_content)
    bind_primary_zone_content_sha1 = sha1(var.bind_primary_zone_file_content)
    # This ensures the rule is (re)created if the agent IP changes between applies,
    # which is unlikely for a single apply but good for robustness.
    devops_agent_ip_trigger        = local.devops_agent_ip
  }

  # ADD THE NSG RULE (runs when null_resource is created/replaced)
  provisioner "local-exec" {
    command = <<EOT
az network nsg rule create \
  --resource-group "${local.untrust_nsg_resource_group_name}" \
  --nsg-name "${local.untrust_nsg_name}" \
  --name "${local.temp_nsg_rule_name_ssh_devops}" \
  --priority ${local.temp_nsg_rule_priority_ssh} \
  --source-address-prefixes "${local.devops_agent_ip}" \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp \
  --description "Temp SSH for DevOps Agent (Terraform)"
EOT
    interpreter = ["bash", "-c"] # Or powershell if your agent uses that by default for az commands
    # This assumes Azure CLI is logged in and configured on the DevOps agent.
  }

  # REMOVE THE NSG RULE (runs when null_resource is destroyed/replaced)
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
az network nsg rule delete \
  --resource-group "${local.untrust_nsg_resource_group_name}" \
  --nsg-name "${local.untrust_nsg_name}" \
  --name "${local.temp_nsg_rule_name_ssh_devops}" || true # Adding "|| true" so it doesn't fail if rule already gone
EOT
    interpreter = ["bash", "-c"]
  }
  depends_on = [azurerm_linux_virtual_machine.nva] # Ensure VM and its NSG exist
}