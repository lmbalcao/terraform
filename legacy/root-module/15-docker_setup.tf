##############################################
# 15-docker_setup.tf
# Configuração Docker com TLS API
##############################################

# Setup Docker básico (instalação)
resource "null_resource" "setup_docker_portainer" {
  for_each = local.enabled_cts

  depends_on = [
    proxmox_lxc.cts
  ]

  triggers = {
    ct_id = proxmox_lxc.cts[each.key].id
  }

  connection {
    type        = "ssh"
    host        = split("/", proxmox_lxc.cts[each.key].network[0].ip)[0]
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y docker.io docker-compose",
      "systemctl enable --now docker",
      "usermod -aG docker root"
    ]
  }
}

# Setup Docker TLS API para acesso remoto seguro
resource "null_resource" "setup_docker_tls_api" {
  for_each = local.enabled_cts

  depends_on = [
    null_resource.setup_docker_portainer
  ]

  triggers = {
    ct_id        = proxmox_lxc.cts[each.key].id
    ct_ip        = proxmox_lxc.cts[each.key].network[0].ip
    portainer_ip = var.portainer_server_ip
  }

  connection {
    type        = "ssh"
    host        = split("/", proxmox_lxc.cts[each.key].network[0].ip)[0]
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo '[INFO] A configurar Docker TLS API...'",
      "HOSTNAME=$(hostname)",
      "IP_CT=$(hostname -I | awk '{print $1}')",
      "CERT_DIR=/etc/docker/certs",
      "CA_KEY=$CERT_DIR/ca-key.pem",
      "CA_CERT=$CERT_DIR/ca.pem",
      "SRV_KEY=$CERT_DIR/server-key.pem",
      "SRV_CSR=$CERT_DIR/server.csr",
      "SRV_CERT=$CERT_DIR/server-cert.pem",
      "mkdir -p $CERT_DIR",
      "chmod 700 $CERT_DIR",
      "[ -z \"$IP_CT\" ] && { echo '[ERRO] IP não determinado'; exit 1; }",
      "if [ ! -f $CA_KEY ] || [ ! -f $CA_CERT ]; then",
      "  echo '[INFO] A gerar CA...'",
      "  openssl genrsa -out $CA_KEY 4096",
      "  openssl req -x509 -new -nodes -key $CA_KEY -sha256 -days 3650 -subj \"/CN=docker-ca-$HOSTNAME\" -out $CA_CERT",
      "  chmod 600 $CA_KEY $CA_CERT",
      "  echo '[OK] CA gerado'",
      "else",
      "  echo '[INFO] CA já existe'",
      "fi",
      "if [ ! -f $SRV_KEY ] || [ ! -f $SRV_CERT ]; then",
      "  echo '[INFO] A gerar certificado servidor...'",
      "  openssl genrsa -out $SRV_KEY 4096",
      "  echo \"subjectAltName = DNS:$HOSTNAME,IP:$IP_CT\" > $CERT_DIR/server-ext.cnf",
      "  echo 'extendedKeyUsage = serverAuth' >> $CERT_DIR/server-ext.cnf",
      "  openssl req -new -key $SRV_KEY -subj \"/CN=$HOSTNAME\" -out $SRV_CSR",
      "  openssl x509 -req -in $SRV_CSR -CA $CA_CERT -CAkey $CA_KEY -CAcreateserial -out $SRV_CERT -days 3650 -sha256 -extfile $CERT_DIR/server-ext.cnf",
      "  rm -f $SRV_CSR $CERT_DIR/server-ext.cnf $CERT_DIR/ca.srl || true",
      "  chmod 600 $SRV_KEY $SRV_CERT",
      "  echo '[OK] Certificado servidor gerado'",
      "else",
      "  echo '[INFO] Certificado servidor já existe'",
      "fi",
      "mkdir -p /etc/systemd/system/docker.service.d",
      "cat > /etc/systemd/system/docker.service.d/override.conf <<OVERRIDE",
      "[Service]",
      "ExecStart=",
      "ExecStart=/usr/sbin/dockerd -H fd:// -H tcp://0.0.0.0:2376 --tlsverify --tlscacert=$CA_CERT --tlscert=$SRV_CERT --tlskey=$SRV_KEY",
      "OVERRIDE",
      "systemctl daemon-reload",
      "systemctl restart docker",
      "sleep 2",
      "echo '[SUCESSO] Docker a escutar em tcp://0.0.0.0:2376 com TLS'",
      "iptables -C INPUT -p tcp -s ${var.portainer_server_ip} --dport 2376 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp -s ${var.portainer_server_ip} --dport 2376 -j ACCEPT",
      "iptables -C INPUT -p tcp --dport 2376 -j DROP 2>/dev/null || iptables -A INPUT -p tcp --dport 2376 -j DROP",
      "command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true",
      "echo '[OK] Firewall configurado'",
      "echo \"[INFO] CA cert: $CA_CERT\""
    ]
  }
}

# Output dos certificados CA
resource "null_resource" "fetch_docker_ca_certs" {
  for_each = local.enabled_cts

  depends_on = [
    null_resource.setup_docker_tls_api
  ]

  triggers = {
    tls_setup_id = null_resource.setup_docker_tls_api[each.key].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/output/docker-certs
      scp -i ${var.ssh_private_key_path} \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        root@${split("/", proxmox_lxc.cts[each.key].network[0].ip)[0]}:/etc/docker/certs/ca.pem \
        ${path.module}/output/docker-certs/${each.key}-ca.pem
      echo "[OK] CA cert copiado: output/docker-certs/${each.key}-ca.pem"
    EOT
  }
}

# Gera certificados de cliente para Portainer
resource "null_resource" "generate_client_certs" {
  for_each = local.enabled_cts

  depends_on = [
    null_resource.setup_docker_tls_api
  ]

  triggers = {
    tls_setup_id = null_resource.setup_docker_tls_api[each.key].id
  }

  connection {
    type        = "ssh"
    host        = split("/", proxmox_lxc.cts[each.key].network[0].ip)[0]
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "cd /etc/docker/certs",
      "if [ ! -f client-key.pem ] || [ ! -f client-cert.pem ]; then",
      "  echo '[INFO] A gerar certificados de cliente...'",
      "  openssl genrsa -out client-key.pem 4096",
      "  openssl req -subj '/CN=client' -new -key client-key.pem -out client.csr",
      "  echo extendedKeyUsage = clientAuth > extfile-client.cnf",
      "  openssl x509 -req -days 365 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out client-cert.pem -extfile extfile-client.cnf",
      "  rm client.csr extfile-client.cnf ca.srl || true",
      "  chmod 600 client-key.pem client-cert.pem",
      "  echo '[OK] Certificados de cliente gerados'",
      "else",
      "  echo '[INFO] Certificados de cliente já existem'",
      "fi"
    ]
  }
}

# Copia TODOS os certificados (CA + client)
resource "null_resource" "fetch_docker_certs" {
  for_each = local.enabled_cts

  depends_on = [
    null_resource.generate_client_certs
  ]

  triggers = {
    client_certs_id = null_resource.generate_client_certs[each.key].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/output/docker-certs
      
      scp -i ${var.ssh_private_key_path} \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        root@${split("/", proxmox_lxc.cts[each.key].network[0].ip)[0]}:/etc/docker/certs/ca.pem \
        ${path.module}/output/docker-certs/${each.key}-ca.pem
      
      scp -i ${var.ssh_private_key_path} \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        root@${split("/", proxmox_lxc.cts[each.key].network[0].ip)[0]}:/etc/docker/certs/client-cert.pem \
        ${path.module}/output/docker-certs/${each.key}-cert.pem
      
      scp -i ${var.ssh_private_key_path} \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        root@${split("/", proxmox_lxc.cts[each.key].network[0].ip)[0]}:/etc/docker/certs/client-key.pem \
        ${path.module}/output/docker-certs/${each.key}-key.pem
      
      echo "[OK] Certificados copiados para output/docker-certs/${each.key}-*.pem"
    EOT
  }
}