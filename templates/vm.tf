resource "proxmox_lxc" "NOME_QUE_EU_QUISER" {
  target_node  = "NOME_DO_NODE"
  hostname     = "teste"
  vmid = "1000"
  description  = "descricao"
  ostemplate = "nas1:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
  password     = var.root_password
  unprivileged = true

  cores  = "1"
  memory = "2048"
  swap = "2048"

  onboot = true
  start  = true

  features { 
    nesting = true
    fuse = true
    keyctl = true
#    mount   = "nfs;cifs"
  }
  
  ssh_public_keys = <<-EOT
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGTjuFbMX06wv9YLknc4UrkNsMnmsan1158Qxfoi+knc root@rundeck
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4xPGgehPGBTd4k/KVWju1arRvzyr3E6H8Sp8wjWEbI vscode-homelab
  EOT

  # DNS (ajusta o IP se o teu DNS não for o gateway)
  nameserver   = "192.168.50.1"
  searchdomain = "lbtec.org"

  rootfs {
    storage = "local"
    size    = "2G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    tag    = 50
    ip     = "192.168.50.125/24"
    gw     = "192.168.50.1"
  }
}
