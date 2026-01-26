resource "proxmox" "lxc-servers" {
  target_node  = "2core"
  hostname     = "teste"
  description  = "descricao"
  ostemplate   = "template-lxc-unpriv"
  unprivileged = true

  cores  = 1
  memory = 2024

  onboot = true
  start  = true

  ssh_public_keys = file("~/.ssh/id_ed25519.pub")

  # DNS (ajusta o IP se o teu DNS não for o gateway)
  nameserver   = "192.168.20.1"
  searchdomain = "lbtec.org"

  rootfs {
    storage = "local"
    size    = "2G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    tag    = 20
    ip     = "192.168.20.125/24"
    gw     = "192.168.20.1"
  }
}
