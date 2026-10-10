# Backend remoto del state en S3.
#
# El nombre del bucket NO se escribe aqui: lo entrega el workflow en
# "terraform init -backend-config=bucket=...", desde la variable de GitHub
# TF_STATE_BUCKET. Asi el codigo no depende de una cuenta de AWS concreta.
#
# use_lockfile (Terraform 1.10+) bloquea el state con un archivo en el propio
# bucket, sin necesitar DynamoDB (que el Learner Lab no siempre habilita).
terraform {
  backend "s3" {
    bucket = "andys-motors-tfstate-chacon-ep2-1791599572"
    key    = "andysmotors/terraform.tfstate"
    region = "us-east-1"
  }
}
