resource "proxmox_lxc" "NOME_QUE_EU_QUISER" {
  target_node  = var.target_node
  hostname     = "teste"
  vmid = "1000"
  description  = "descricao"
  ostemplate   = var.ostemplate
  password     = var.root_password
  unprivileged = true

  cores  = "1"
  memory = "2048"
  swap = "2048"

  onboot = true
  start  = true

  features { 
    nesting = true
  }
  
  ssh_public_keys = join("\n", var.ssh_public_keys)

  # DNS (ajusta o IP se o teu DNS não for o gateway)
  nameserver = "192.168.17.1"
  searchdomain = var.searchdomain

  rootfs {
    storage = var.storage
    size    = "2G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    tag    = "17"
    ip     = "192.168.17.125/24"
    gw     = "192.168.17.1"
  }
}
