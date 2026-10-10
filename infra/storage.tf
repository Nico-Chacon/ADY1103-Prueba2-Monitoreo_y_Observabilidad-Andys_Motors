
# ---------------------------------------------------------------------------
# Amazon S3: archivos, documentos, imagenes, respaldos y reportes.
# Se reutiliza un bucket creado previamente en AWS Academy.
# ---------------------------------------------------------------------------

locals {
  documentos_bucket = "andys-motors-documentos-chacon-ep2-20261010"
}

# ---------------------------------------------------------------------------
# Distribucion del entorno de Andys Motors a los servidores
# ---------------------------------------------------------------------------

data "archive_file" "demo" {
  type        = "zip"
  source_dir  = "${path.module}/../demo"
  output_path = "${path.module}/.terraform/tmp/demo.zip"

  excludes = concat(
    [".env", ".gitignore", "README.md"],
    [
      for f in fileset("${path.module}/../demo", "app/node_modules/**") : f
    ],
    [
      for f in fileset("${path.module}/../demo", "scripts/__pycache__/**") : f
    ],
  )
}

resource "aws_s3_object" "demo" {
  bucket = local.documentos_bucket
  key    = "entorno/demo.zip"
  source = data.archive_file.demo.output_path
  etag   = data.archive_file.demo.output_md5
}
