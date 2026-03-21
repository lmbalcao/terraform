locals {
  cts = {
    ct_template_u_sp = {
      enabled       = true
      vlan          = 17
      ultimo_octeto = 50
      target_node   = "2core"
      hostname      = "usf"
      description   = "Teste Unpriv"
      tags          = []
      ostemplate    = var.ostemplate
      unprivileged  = true

      cores  = 1
      memory = 2048
      swap   = 1024

      onboot = true
      start  = true

      storage = "local"
      size    = "2G"

      # ✅ Features agora são lidas dinamicamente
      features = {
        nesting = false
        fuse    = false
        keyctl  = false
        # mount = "nfs;cifs"  # Opcional
      }

      apps = []
    }
  }
}  