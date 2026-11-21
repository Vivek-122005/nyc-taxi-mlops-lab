# S1: wire the Redshift cluster (infra/modules/redshift) into this root module, and expose the
# outputs that contracts/platform.yaml lists under terraform_outputs.

module "redshift" {
  source = "../modules/redshift"

  name              = "lab"
  database          = "lab"
  subnet_ids        = data.aws_subnets.default.ids
  availability_zone = var.availability_zone
}

output "redshift_cluster_id" {
  value = module.redshift.cluster_id
}

output "redshift_database" {
  value = module.redshift.database
}
