# Spoke Network Module (Using AzAPI for Subnets)

## Overview

This Terraform module provisions Azure spoke virtual networks, including their subnets, Network Security Groups (NSGs), Route Tables (RTs), VNet peering to a central hub, and Private DNS Zone links.

This module utilizes the `azapi_resource` provider to define and manage subnets (`Microsoft.Network/virtualNetworks/subnets`). This specific implementation was selected after evaluating alternative approaches and identifying significant technical limitations with each.

## Implementation History and Rationale

Creating a maintainable Terraform module for Azure subnets that integrates correctly with NSGs, Route Tables, delegations, and Azure Policy presented several challenges. The following approaches were evaluated:

### 1. AVM Module Approach (`spoke-network-with-avm`) - Discarded

* **Method:** Employed the official `Azure/avm-res-network-virtualnetwork/azurerm` module within a `for_each` loop to manage VNets and subnets.
* **Identified Issue:** Modifying the input set of virtual networks (e.g., adding or removing a spoke VNet definition) resulted in Terraform planning the destruction and recreation of *all existing* VNet instances managed by the module.
* **Analysis:** This behavior is likely due to complexities in dependency calculation or output referencing when using the AVM module within a `for_each` construct, potentially related to values known only after apply.
* **Outcome:** This approach proved unsuitable for iterative deployments or managing an evolving set of spoke networks due to the unintended resource replacement.

### 2. Separate `azurerm_subnet` Resource Approach (`spoke-network-azurerm-subnet`) - Discarded

* **Method:** Defined VNets (`azurerm_virtual_network`), subnets (`azurerm_subnet`), and associated NSGs/RTs using separate association resources (`azurerm_subnet_network_security_group_association`, `azurerm_subnet_route_table_association`).
* **Identified Issues:**
    * **Azure Policy Timing Conflict:** The subnet resource is created *before* the NSG association. This conflicts with Azure Policies mandating that subnets have an NSG upon creation, necessitating the policy be set to "Audit" mode, which may not align with security requirements.
    * **Delegation Lifecycle Management:** Azure automatically populates the `actions` attribute within subnet delegations. To prevent persistent configuration drift detected by Terraform, `ignore_changes = [delegation]` was required on the `azurerm_subnet` resource. This ignores the *entire* delegation block, preventing Terraform from managing intentional changes to the delegation's service name or other properties. Ignoring only the nested `actions` attribute (`delegation.service_delegation.actions`) is not syntactically supported by Terraform's `ignore_changes`.
* **Outcome:** This method required policy exceptions and employed non-granular lifecycle management for delegations, making it suboptimal.

### 3. Inline `subnet` Block Approach (`spoke-network-inline-subnets`) - Discarded

* **Method:** Defined subnets using the inline `subnet` block directly within the `azurerm_virtual_network` resource. This resolves the Azure Policy timing conflict for NSG association.
* **Identified Issue:** This approach reintroduced the delegation `actions` drift issue. Because the subnet is defined *within* the VNet resource via a dynamic block, Terraform's `ignore_changes` cannot target the nested `actions` attribute within a specific subnet's delegation. Ignoring the entire `subnet` block or the parent `azurerm_virtual_network` is not feasible as it would prevent Terraform from managing any other configuration changes on those resources.
* **Outcome:** While addressing the policy timing, this method created an unmanageable configuration drift scenario related to subnet delegations.

### 4. AzAPI Subnet Approach (This Module) - Selected

* **Method:** Defines VNets, NSGs, and RTs using standard `azurerm` resources. Defines subnets using the `azapi_resource` targeting `Microsoft.Network/virtualNetworks/subnets`. NSG and RT associations are specified as properties directly within the `body` of the `azapi_resource`.
* **Advantages Resolved:**
    * **Policy Compliance:** NSG and RT associations are defined as part of the subnet creation payload via the API, satisfying Azure Policy timing requirements without needing "Audit" mode.
    * **Avoids AVM Resource Churn:** Does not rely on the external AVM module structure that led to destructive plans.
    * **Improved Lifecycle for Delegations:** By defining the subnet via AzAPI and omitting the `actions` property from the request body, Azure manages these default actions. Terraform's `ignore_changes` can still be applied granularly to other properties within the `body` if necessary (e.g., `body.properties.ipConfigurations`, `body.properties.privateEndpoints` are ignored by default as they are often modified externally). This avoids the need to ignore the entire delegation block.
* **Technical Considerations:**
    * Requires the `Azure/azapi` provider dependency.
    * Configuration interacts directly with the Azure Resource Manager API schema for subnets, which is less abstracted than dedicated `azurerm` resources. Check the API version specified (`2023-11-01` in this module) for compatibility.
    * Concurrency: Initial deployment may encounter `409 Conflict - AnotherOperationInProgress` errors if creating many subnets in the same VNet simultaneously. Running `terraform apply -parallelism=1` resolves this by serializing operations.

## Conclusion

After evaluating the technical limitations associated with alternative methods, utilizing `azapi_resource` for subnet definition was determined to be the most stable and suitable approach. It directly addresses the critical issues related to Azure Policy compliance, resource churn observed with the AVM module, and the delegation lifecycle management challenges encountered with both separate and inline `azurerm` subnet definitions. While requiring direct API schema interaction and potentially needing parallelism control during applies, this method provides a functional and maintainable solution.