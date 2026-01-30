locals {
  cts = {
    ct_web = {
      enabled         = true
      vlan            = 17
      ultimo_octeto   = 66 # Sempre entre 2 e 254
      target_node     = "2core"
      hostname        = "teste-homarr"
      description     = "Criação e Deploy de Homarr"
      ostemplate      = var.ostemplate
      unprivileged    = true

      cores  = 1
      memory = 2048
      swap   = 1024

      onboot = true
      start  = true

      storage = "local"
      size    = "8G"

      features = {
        nesting = true
      }

      # NOVO
      apps = ["homarr"]
    }

    ct_db = {
      enabled         = false
      vlan            = 60
      ultimo_octeto   = 66
      target_node     = "4core"
      hostname        = "teste-db"
      description     = "descricao db"
      ostemplate      = var.ostemplate
      unprivileged    = true

      cores  = 2
      memory = 2048
      swap   = 2048

      onboot = true
      start  = true

      storage = "local"
      size    = "2G"

      # NOVO (explícito, mesmo que vazio)
      apps = []
    }
  }
}
