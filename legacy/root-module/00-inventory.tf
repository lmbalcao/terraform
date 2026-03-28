###############################################################################
# inventory.tf - Inventário (CORRIGIDO)
# - Fecha chaves em falta
# - Normaliza mountpoints (lista de objetos) para todos os CTs
###############################################################################

locals {
  cts = {
    homarr = {
      enabled       = true
      vlan          = 60
      ultimo_octeto = 11
      target_node   = "2core"
      hostname      = "homarr"
      tags          = ["60-servicos-externos"]
      ostemplate    = var.ostemplate
      unprivileged  = true

      cores  = 2
      memory = 2048
      swap   = 1024

      onboot = true
      start  = true

      storage = "local"
      size    = "8G"

      features = {
        nesting = true
      }

      features_manual = {
        keyctl = false
        fuse   = false
        mount  = ""
        create = false
      }

      controlo_manual = {
        run_restic_restore = false
        run_rundeck        = false
      }

      apps = ["homarr"]

      mountpoints = []
    }
  }

  vms = {
    vm_template = {
      enabled       = false
      vlan          = 17
      ultimo_octeto = 80
      target_node   = "6core"
      name          = "vm-template"
      tags          = []

      cores   = 2
      sockets = 1
      memory  = 2048

      start_at_node_boot = true
      vm_state           = "running"

      storage = "local"
      size    = "20G"

      controlo_manual = {
        run_restic_restore = false
        run_rundeck        = false
      }

      clone      = null
      ostemplate = var.ostemplate
    }
  }

  # Filtra apenas recursos enabled
  enabled_cts = {
    for name, ct in local.cts : name => ct
    if lookup(ct, "enabled", true)
  }

  enabled_vms = {
    for name, vm in local.vms : name => vm
    if lookup(vm, "enabled", true)
  }
}
