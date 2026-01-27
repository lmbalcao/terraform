locals {
  cts = {
    ct_web = {
      enabled      = false
      vlan         = 17
      campo_meu    = 33
      target_node  = "2core"
      hostname     = "teste-web"
      description  = "descricao web"
      ostemplate   = var.ostemplate
      unprivileged = true

      cores  = 1
      memory = 2048
      swap   = 1024

      onboot = true
      start  = true

      storage = "local"
      size    = "2G"

      features = {
        nesting = true
      }
    }

    ct_db = {
      enabled      = false
      vlan         = 60
      campo_meu    = 158
      target_node  = "4core"
      hostname     = "teste-db"
      description  = "descricao db"
      ostemplate   = var.ostemplate
      unprivileged = false

      cores  = 2
      memory = 2048
      swap   = 2048

      onboot = true
      start  = true

      storage = "local"
      size    = "2G"
    }
  }
}
