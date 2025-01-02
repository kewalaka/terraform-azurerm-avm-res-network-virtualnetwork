resource "azapi_resource" "management_lock" {
  count = (var.lock != null ? 1 : 0)

  type = "Microsoft.Authorization/locks@2020-05-01"
  body = {
    properties = {
      level = var.lock.kind
      notes = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
    }
  }
  name      = coalesce(var.lock.name, "lock-${var.lock.kind}")
  parent_id = azapi_resource.vnet.id

  depends_on = [
    azapi_resource.vnet
  ]
}

data "azapi_resource_list" "role_definition" {
  for_each = local.role_assignments_by_name

  parent_id = "/subscriptions/${local.subscription_id}"
  type      = "Microsoft.Authorization/roleDefinitions@2022-05-01-preview"
  query_parameters = {
    "$filter" = ["roleName eq '${each.value.role_definition_id_or_name}'"]
  }
  response_export_values = {
    "values" = "value[].{id: id}"
  }
}

# a random uuid resource is used so the id is recorded in state, if just using uuid() the id would be different each time
resource "random_uuid" "role_assignment" {
  for_each = var.role_assignments
}

resource "azapi_resource" "role_assignment" {
  for_each = var.role_assignments

  type = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      principalId                        = each.value.principal_id
      roleDefinitionId                   = local.role_definition_id_map[each.key]
      condition                          = each.value.condition
      conditionVersion                   = each.value.condition_version
      delegatedManagedIdentityResourceId = each.value.delegated_managed_identity_resource_id
      description                        = each.value.description
    }
  }
  name                   = random_uuid.role_assignment[each.key].result
  parent_id              = azapi_resource.vnet.id
  response_export_values = []

  depends_on = [
    azapi_resource.vnet
  ]

  lifecycle {
    ignore_changes = [
      name,
    ]
  }
}

resource "azapi_resource" "diagnostic_setting" {
  for_each = var.diagnostic_settings

  type = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  body = {
    properties = {
      eventHubAuthorizationRuleId = each.value.event_hub_authorization_rule_resource_id
      eventHubName                = each.value.event_hub_name
      logAnalyticsDestinationType = each.value.log_analytics_destination_type == "Dedicated" ? null : each.value.log_analytics_destination_type
      workspaceId                 = each.value.workspace_resource_id
      marketplacePartnerId        = each.value.marketplace_partner_resource_id
      storageAccountId            = each.value.storage_account_resource_id

      logs = concat([
        for log_category in each.value.log_categories : {
          category      = log_category
          categoryGroup = ""
          enabled       = true
          retentionPolicy = {
            days    = 0
            enabled = false
          }
        }],
        [for log_group in each.value.log_groups : {
          category      = ""
          categoryGroup = log_group
          enabled       = true
          retentionPolicy = {
            days    = 0
            enabled = false
          }
        }]
      )
      metrics = [
        for metric_category in each.value.metric_categories : {
          category = metric_category
          enabled  = true
          retentionPolicy = {
            enabled = true
            days    = 0
          }
        }
      ]
    }
  }
  name      = each.value.name != null ? each.value.name : "diag-${var.name}"
  parent_id = azapi_resource.vnet.id
  # in order for 'location' to be accepted within the lifecycle block, schema validation must be turned off :-(
  schema_validation_enabled = false

  # ref: ignoring the location is required due to a spec bug upstream in the REST API, ref: https://github.com/Azure/terraform-provider-azapi/issues/655
  # the resource will be created ok, but without this set there is a diff on every apply
  lifecycle {
    ignore_changes = [
      location,
    ]
  }
}

moved {
  from = azurerm_role_assignment.vnet_level
  to   = azapi_resource.role_assignment
}

moved {
  from = azurerm_monitor_diagnostic_setting.this
  to   = azapi_resource.diagnostic_setting
}
