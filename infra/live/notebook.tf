# S2: wire infra/modules/notebook (the SageMaker notebook) into this root module, let it reach MLflow
# on the platform host (port 5000, runtime.yaml), and output its name as notebook_name.
# Set github_repo in terraform.tfvars: the notebook clones your public repo.

module "notebook" {
  source = "../modules/notebook"

  name      = "lab"
  subnet_id = data.aws_subnet.hosts.id
  repo_url  = "https://github.com/${var.github_repo}.git"
  env = {
    MLFLOW_TRACKING_URI = "http://${module.platform.private_ip}:5000"
    REDSHIFT_CLUSTER_ID = module.redshift.cluster_id
    REDSHIFT_DATABASE   = module.redshift.database
    REDSHIFT_DB_USER    = "labadmin"
    LAB_ARTIFACT_BUCKET = module.artifacts.name
  }
}

resource "aws_vpc_security_group_ingress_rule" "platform_mlflow_from_notebook" {
  security_group_id            = aws_security_group.platform.id
  description                  = "MLflow from SageMaker notebook"
  ip_protocol                  = "tcp"
  from_port                    = 5000
  to_port                      = 5000
  referenced_security_group_id = module.notebook.security_group_id
}

output "notebook_name" {
  value = module.notebook.name
}
