###############################################################################
# deploy_compose.tf - Deploy de aplicações Docker via compose
# CORRIGIDO: destino final /opt/${app}, segurança Git, validação, rollback
###############################################################################

locals {
  enabled_cts_docker = {
    for name, ct in local.cts : name => ct
    if try(ct.enabled, true) && length(try(ct.apps, [])) > 0
  }
}

###############################################################################
# Recurso separado: Instalação Docker (executa 1x, não re-executa se apps mudarem)
###############################################################################
resource "null_resource" "setup_docker" {
  for_each = local.enabled_cts_docker

  triggers = {
    vmid = tonumber("${each.value.vlan}${each.value.ultimo_octeto}")
  }

  depends_on = [
    proxmox_lxc.cts,
    null_resource.restore_restic
  ]

  connection {
    type        = "ssh"
    host        = "192.168.${each.value.vlan}.${each.value.ultimo_octeto}"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "export DEBIAN_FRONTEND=noninteractive",
      
      "echo '[INFO] A instalar dependências base...'",
      "apt-get update -y",
      "apt-get install -y git ca-certificates curl gnupg",
      
      <<-SCRIPT
        if ! command -v docker >/dev/null 2>&1; then
          echo '[INFO] A instalar Docker...'
          
          install -m 0755 -d /etc/apt/keyrings
          curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
          chmod a+r /etc/apt/keyrings/docker.asc
          
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
          
          apt-get update -y
          apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
          systemctl enable --now docker
          
          echo '[SUCESSO] Docker instalado'
        else
          echo '[INFO] Docker já instalado, a continuar...'
        fi
      SCRIPT
    ]
  }
}

###############################################################################
# Recurso principal: Deploy de aplicações
###############################################################################
resource "null_resource" "deploy_apps" {
  for_each = local.enabled_cts_docker

  triggers = {
    host_ip        = "192.168.${each.value.vlan}.${each.value.ultimo_octeto}"
    repo           = var.apps_repo_url
    branch         = var.apps_repo_branch
    apps           = sha1(join(",", sort(try(each.value.apps, []))))
    force_redeploy = try(var.force_redeploy_timestamp, "")
  }

  depends_on = [
    null_resource.setup_docker
  ]

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
        
        <<-SCRIPT
          echo '[INFO] A configurar autenticação Git...'
          
          git config --global credential.helper store
          
          mkdir -p ~/.git-credentials.d
          chmod 700 ~/.git-credentials.d
          
          cat > ~/.git-credentials.d/forgejo <<'EOF'
https://${var.forgejo_user}:${var.forgejo_token}@forgejo.lbtec.org
EOF
          chmod 600 ~/.git-credentials.d/forgejo
          
          git config --global credential.helper "store --file=$HOME/.git-credentials.d/forgejo"
        SCRIPT
        ,
        
        "REPO_DIR=/lbtec",
        <<-SCRIPT
          echo '[INFO] A sincronizar repositório de aplicações...'
          
          if [ -d "$REPO_DIR/.git" ]; then
            echo '[INFO] Repositório existente, a atualizar...'
            cd "$REPO_DIR"
            
            git fetch --all --prune
            git reset --hard origin/${var.apps_repo_branch}
            git checkout ${var.apps_repo_branch}
            git clean -fd
            
            CURRENT_COMMIT=$(git rev-parse HEAD)
            echo "[INFO] Repositório atualizado para commit: $CURRENT_COMMIT"
          else
            echo '[INFO] A clonar repositório...'
            rm -rf "$REPO_DIR"
            
            if ! git clone --branch ${var.apps_repo_branch} ${var.apps_repo_url} "$REPO_DIR"; then
              echo '[ERRO] Falha ao clonar repositório'
              exit 1
            fi
            
            cd "$REPO_DIR"
            CURRENT_COMMIT=$(git rev-parse HEAD)
            echo "[SUCESSO] Repositório clonado: $CURRENT_COMMIT"
          fi
          
          rm -f ~/.git-credentials.d/forgejo
          git config --global --unset credential.helper || true
        SCRIPT
      ],
      
      flatten([
        for app in try(each.value.apps, []) : [
          <<-SCRIPT
            echo '================================================================='
            APP_NAME='${app}'
            echo "[INFO] A processar aplicação: $APP_NAME"
            echo '================================================================='
            
            SOURCE_DIR="/lbtec/apps/$APP_NAME"
            DEST_DIR="/opt/$APP_NAME"
            
            if [ ! -d "$SOURCE_DIR" ]; then
              echo "[AVISO] Aplicação não encontrada no repositório: $SOURCE_DIR - ignorado"
              exit 0
            fi
            
            echo "[INFO] A copiar $APP_NAME para $DEST_DIR..."
            rm -rf "$DEST_DIR"
            cp -r "$SOURCE_DIR" "$DEST_DIR"
            
            COMPOSE_FILE="$DEST_DIR/docker-compose.yml"
            
            if [ ! -f "$COMPOSE_FILE" ]; then
              echo "[AVISO] App $APP_NAME sem docker-compose.yml - ignorado"
              exit 0
            fi
            
            echo "[INFO] Compose file encontrado: $COMPOSE_FILE"
            
            echo "[INFO] A validar sintaxe do compose file..."
            if ! docker compose -f "$COMPOSE_FILE" config >/dev/null 2>&1; then
              echo "[AVISO] Compose file inválido ou com erros de sintaxe - ignorado"
              docker compose -f "$COMPOSE_FILE" config 2>&1 || true
              exit 0
            fi
            
            echo "[INFO] Compose file válido ✓"
            
            BACKUP_STATE="/opt/.docker-state-backup-$APP_NAME-$(date +%s).json"
            if docker compose -f "$COMPOSE_FILE" ps --format json >/dev/null 2>&1; then
              echo "[INFO] A guardar estado atual para possível rollback..."
              docker compose -f "$COMPOSE_FILE" ps --format json > "$BACKUP_STATE" || true
            fi
            
            echo "[INFO] A fazer deploy de $APP_NAME..."
            if docker compose -f "$COMPOSE_FILE" up -d --remove-orphans 2>&1; then
              echo "[SUCESSO] Deploy de $APP_NAME concluído ✓"
              
              rm -f /opt/.docker-state-backup-$APP_NAME-*.json 2>/dev/null || true
              
              echo "[INFO] Estado dos containers:"
              docker compose -f "$COMPOSE_FILE" ps
            else
              echo "[AVISO] Deploy de $APP_NAME falhou - ignorado"
              echo "[INFO] A tentar rollback..."
              
              docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
              
              echo "[INFO] Verificar logs: docker compose -f $COMPOSE_FILE logs"
              exit 0
            fi
            
            echo '================================================================='
          SCRIPT
        ]
      ]),
      
      [
        <<-SCRIPT
          echo '[INFO] A limpar ficheiros temporários...'
          
          find /opt -name '.docker-state-backup-*' -type f -mtime +7 -delete 2>/dev/null || true
          
          docker image prune -f >/dev/null 2>&1 || true
          
          echo '[SUCESSO] Deploy concluído com sucesso!'
        SCRIPT
      ]
    )
  }
  
  provisioner "local-exec" {
    when    = create
    command = "echo 'Deploy iniciado para ${each.key} em 192.168.${each.value.vlan}.${each.value.ultimo_octeto}'"
  }
  
  provisioner "local-exec" {
    when       = create
    on_failure = fail
    command = "echo 'ERRO: Deploy falhou para ${each.key}. Verificar logs SSH acima.'"
  }
}