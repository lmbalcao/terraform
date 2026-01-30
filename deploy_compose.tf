locals {
  enabled_cts_docker = {
    for name, ct in local.cts : name => ct
    if try(ct.enabled, true)
  }

  # Se token existir, inject no URL: https://<token>@forgejo...
  apps_repo_url_auth = (
    length(var.forgejo_token) > 0
    ? replace(var.apps_repo_url, "https://", "https://${var.forgejo_user}:${var.forgejo_token}@")
    : var.apps_repo_url
  )
}

resource "null_resource" "deploy_apps" {
  for_each = local.enabled_cts_docker

  triggers = {
    host_ip = "192.168.${each.value.vlan}.${each.value.ultimo_octeto}"
    repo    = var.apps_repo_url
    branch  = var.apps_repo_branch
    apps    = sha1(join(",", sort(try(each.value.apps, []))))
  }

  depends_on = [proxmox_lxc.cts]

  connection {
    type        = "ssh"
    host        = "192.168.${each.value.vlan}.${each.value.ultimo_octeto}"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = concat(
      [
        "set -euo pipefail",
        "export DEBIAN_FRONTEND=noninteractive",

        "apt-get update -y",
        "apt-get install -y git ca-certificates curl",

        # Docker + compose plugin
        <<-SH
          if ! command -v docker >/dev/null 2>&1; then
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
            chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
            apt-get update -y
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            systemctl enable --now docker
          fi
        SH
        ,

        # Checkout repo
        "REPO_DIR=/opt/lbtec",
        <<-SH
          if [ -d "$REPO_DIR/.git" ]; then
            cd "$REPO_DIR"
            git fetch --all
            git checkout ${var.apps_repo_branch}
            git pull
          else
            rm -rf "$REPO_DIR"
            git clone --branch ${var.apps_repo_branch} ${local.apps_repo_url_auth} "$REPO_DIR"
          fi
        SH
      ],
      [
        for app in try(each.value.apps, []) : <<-CMD
          COMPOSE_FILE="/opt/lbtec/apps/${app}/docker-compose.yml"
          test -f "$COMPOSE_FILE" || (echo "ERRO: compose não encontrado: $COMPOSE_FILE" && exit 2)
          docker compose -f "$COMPOSE_FILE" up -d --remove-orphans
        CMD
      ]
    )
  }
}
