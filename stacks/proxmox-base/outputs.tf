output "inventory_summary" {
  value = {
    environment = var.environment
    cts         = sort(keys(local.cts))
    vms         = sort(keys(local.vms))
  }
}

output "created_cts" {
  value = {
    for name, mod in module.cts : name => {
      vmid       = mod.vmid
      hostname   = mod.hostname
      node       = mod.target_node
      ip         = mod.ipv4_address
      tags       = try(local.cts[name].tags, [])
      services   = try(local.cts[name].services, [])
      operations = try(local.cts[name].operations, {})
    }
  }
}

output "created_vms" {
  value = {
    for name, mod in module.vms : name => {
      vmid       = mod.vmid
      name       = mod.name
      node       = mod.target_node
      address    = mod.network_address
      tags       = try(local.vms[name].tags, [])
      services   = try(local.vms[name].services, [])
      operations = try(local.vms[name].operations, {})
    }
  }
}

output "ansible_targets" {
  value = merge(
    {
      for name, mod in module.cts : name => {
        kind            = "ct"
        name            = name
        node            = mod.target_node
        address         = mod.ipv4_address
        tags            = try(local.cts[name].tags, [])
        ansible_enabled = try(local.cts[name].operations.ansible_enabled, false)
      }
    },
    {
      for name, mod in module.vms : name => {
        kind            = "vm"
        name            = name
        node            = mod.target_node
        address         = mod.network_address
        tags            = try(local.vms[name].tags, [])
        ansible_enabled = try(local.vms[name].operations.ansible_enabled, false)
      }
    }
  )
}

output "pbs_targets" {
  value = merge(
    {
      for name, mod in module.cts : name => {
        kind          = "ct"
        vmid          = mod.vmid
        node          = mod.target_node
        tags          = try(local.cts[name].tags, [])
        backup_policy = try(local.cts[name].operations.backup_policy, null)
      }
    },
    {
      for name, mod in module.vms : name => {
        kind          = "vm"
        vmid          = mod.vmid
        node          = mod.target_node
        tags          = try(local.vms[name].tags, [])
        backup_policy = try(local.vms[name].operations.backup_policy, null)
      }
    }
  )
}
