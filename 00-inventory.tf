locals {
  cts = {
    ct_teste = {
      enabled         = true
      vlan            = 35
      ultimo_octeto   = 99
      target_node     = "2core"
      hostname        = "teste-com-homarr"
      description     = "Criação e Deploy de Homarr"
      tags            = ["teste", "terraform"]
      ostemplate      = var.ostemplate
      unprivileged    = true

      cores  = 1
      memory = 2048
      swap   = 1024

      onboot = true
      start  = true

      storage = "local"
      size    = "8G"

      # ✅ Features agora são lidas dinamicamente
      features = {
        nesting = true
        fuse    = false
        keyctl  = false
        # mount = "nfs;cifs"  # Opcional
      }

      apps = ["sonarr"]
    }

    ct_web = {
      enabled         = true
      vlan            = 17
      ultimo_octeto   = 45
      target_node     = "4core"
      hostname        = "teste4core"
      description     = "Criação e Deploy de Homarr"
      tags            = ["teste", "terraform"]
      ostemplate      = var.ostemplate
      unprivileged    = true

      cores  = 1
      memory = 2048
      swap   = 1024

      onboot = true
      start  = true

      storage = "local"
      size    = "8G"

      # ✅ Features agora são lidas dinamicamente
      features = {
        nesting = true
        fuse    = false
        keyctl  = false
        # mount = "nfs;cifs"  # Opcional
      }

      apps = ["homarr"]
    }

    ct_db = {
      enabled         = true
      vlan            = 17
      ultimo_octeto   = 67
      target_node     = "6core"
      hostname        = "teste-db"
      description     = "descricao db"
      tags            = ["teste", "terraform"]      
      ostemplate      = var.ostemplate
      unprivileged    = true

      cores  = 2
      memory = 2048
      swap   = 2048

      onboot = true
      start  = true

      storage = "local"
      size    = "2G"

      # ✅ Se não especificares, usa defaults (nesting=true, resto=false)
      # features = {}  # Opcional, pode omitir

      apps = ["rambo", "authentik", "sonarr"]
    }
  }
}