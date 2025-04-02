module "avm_interfaces" {
  source  = "Azure/avm-utl-interfaces/azure"
  version = "0.2.0"

  diagnostic_settings              = var.diagnostic_settings
  lock                             = var.lock
  role_assignments                 = var.role_assignments
  role_assignment_definition_scope = "/subscriptions/${data.azapi_client_config.this.subscription_id}"
}

resource "azapi_resource" "role_assignment" {
  for_each = module.avm_interfaces.role_assignments_azapi

  type      = each.value.type
  body      = each.value.body
  locks     = [azapi_resource.vnet.id]
  name      = each.value.name
  parent_id = azapi_resource.vnet.id
}

resource "azapi_resource" "diagnostic_settings" {
  for_each = module.avm_interfaces.diagnostic_settings_azapi

  type      = each.value.type
  body      = each.value.body
  locks     = [azapi_resource.vnet.id]
  name      = each.value.name
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

resource "azapi_resource" "lock" {
  count = module.avm_interfaces.lock_azapi != null ? 1 : 0

  type      = lookup(module.avm_interfaces.lock_azapi, "type", null)
  body      = lookup(module.avm_interfaces.lock_azapi, "body", null)
  locks     = [azapi_resource.vnet.id]
  name      = lookup(module.avm_interfaces.lock_azapi, "name", null)
  parent_id = azapi_resource.vnet.id
}

moved {
  from = azurerm_role_assignment.vnet_level
  to   = azapi_resource.role_assignment
}

moved {
  from = azurerm_monitor_diagnostic_setting.this
  to   = azapi_resource.diagnostic_setting
}
