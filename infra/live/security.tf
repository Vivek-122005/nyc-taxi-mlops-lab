# S0: security groups and rules.
#
# Decision point: who may reach the app (ingress scope)? That is var.ingress_cidrs, set in
# terraform.tfvars and recorded in decisions/.
# Traffic between hosts (ports in contracts/runtime.yaml):
#   app -> platform  MLflow
#   app, platform -> llm  chat and embeddings
#   app, platform -> rds  Postgres
# There is no SSH in this lab: use SSM Session Manager for a shell and port forwarding for UIs.
# No rule opens port 22, and nothing but Traefik (80) is reachable from outside the VPC.

resource "aws_security_group" "app" {
  name        = "lab-app"
  description = "App host: Traefik on 80 from ingress_cidrs only"
  vpc_id      = data.aws_vpc.default.id
  tags        = { Name = "lab-app" }
}

resource "aws_security_group" "platform" {
  name        = "lab-platform"
  description = "Platform host: Dagster and MLflow, no public ingress"
  vpc_id      = data.aws_vpc.default.id
  tags        = { Name = "lab-platform" }
}

resource "aws_security_group" "llm" {
  name        = "lab-llm"
  description = "LLM host: chat and embeddings from app and platform"
  vpc_id      = data.aws_vpc.default.id
  tags        = { Name = "lab-llm" }
}

resource "aws_security_group" "rds" {
  name        = "lab-rds"
  description = "Postgres from app and platform"
  vpc_id      = data.aws_vpc.default.id
  tags        = { Name = "lab-rds" }
}

# --- ingress -------------------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  for_each          = toset(var.ingress_cidrs)
  security_group_id = aws_security_group.app.id
  description       = "Traefik"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "platform_mlflow_from_app" {
  security_group_id            = aws_security_group.platform.id
  description                  = "MLflow from app"
  ip_protocol                  = "tcp"
  from_port                    = 5000
  to_port                      = 5000
  referenced_security_group_id = aws_security_group.app.id
}

locals {
  llm_ports = { chat = 8080, embed = 8081 }
  # Every (client SG, llm port) pair.
  llm_rules = {
    for pair in setproduct(["app", "platform"], keys(local.llm_ports)) :
    "${pair[0]}-${pair[1]}" => { client = pair[0], port = local.llm_ports[pair[1]] }
  }
  client_sgs = {
    app      = aws_security_group.app.id
    platform = aws_security_group.platform.id
  }
}

resource "aws_vpc_security_group_ingress_rule" "llm" {
  for_each                     = local.llm_rules
  security_group_id            = aws_security_group.llm.id
  description                  = "llm ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = local.client_sgs[each.value.client]
}

resource "aws_vpc_security_group_ingress_rule" "rds" {
  for_each                     = local.client_sgs
  security_group_id            = aws_security_group.rds.id
  description                  = "Postgres from ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = each.value
}

# --- egress --------------------------------------------------------------------------------------
# Hosts need outbound internet (dnf, GHCR, GitHub's runner service, SSM endpoints) and the intra-VPC
# ports above. RDS needs no egress rule: replies to allowed inbound traffic are stateful.

resource "aws_vpc_security_group_egress_rule" "hosts_all" {
  for_each          = { app = aws_security_group.app.id, platform = aws_security_group.platform.id, llm = aws_security_group.llm.id }
  security_group_id = each.value
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
