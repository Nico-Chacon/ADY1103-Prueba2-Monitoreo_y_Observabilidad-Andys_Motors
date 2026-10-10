# ---------------------------------------------------------------------------
# Topologia del despliegue
#
# El caso describe seis plataformas. Cada una puede tener su propio servidor, o
# pueden compartir uno solo. Cambiar de una cosa a la otra es una decision de
# despliegue, no de codigo: el entorno es el mismo y usa los mismos perfiles de
# Docker Compose.
# ---------------------------------------------------------------------------

locals {
  # Puerto en el que escucha cada plataforma. Es el mismo dentro y fuera del
  # contenedor, para que la direccion no cambie entre modos de despliegue.
  puertos = {
    web    = 8081
    stock  = 8082
    agenda = 8083
    crm    = 8084
    pagos  = 8085
  }

  # Una maquina por plataforma, como describe el caso.
  servidores_completa = merge(
    var.enable_rds ? {} : { data = { perfiles = "data", rol = "base-de-datos" } },
    {
      stock  = { perfiles = "stock", rol = "aplicacion" }
      agenda = { perfiles = "agenda", rol = "aplicacion" }
      crm    = { perfiles = "crm", rol = "aplicacion" }
      pagos  = { perfiles = "pagos", rol = "aplicacion" }
      web    = { perfiles = "web", rol = "aplicacion" }
      borde  = { perfiles = "borde", rol = "borde" }
    }
  )

  # Todas las plataformas en una sola maquina, mas el balanceador. Sirve cuando
  # la cuota de instancias del laboratorio no alcanza para siete servidores.
  servidores_compacta = {
    app = {
      perfiles = var.enable_rds ? "stock,agenda,crm,pagos,web" : "data,stock,agenda,crm,pagos,web"
      rol      = "aplicacion"
    }
    borde = { perfiles = "borde", rol = "borde" }
  }

  servidores = var.topologia == "compacta" ? local.servidores_compacta : local.servidores_completa

  # --- Direcciones IP privadas, asignadas por adelantado --------------------
  #
  # Cada servidor necesita conocer las direcciones de los demas dentro de su
  # script de arranque. Si dejaramos que AWS las asignara, Terraform tendria que
  # leer la IP de una instancia para construir otra instancia del mismo recurso,
  # lo que es una referencia circular y no se puede resolver.
  #
  # La solucion es fijarlas nosotros a partir del rango de la subred. Ademas
  # tienen la ventaja de que no cambian nunca, ni siquiera al recrear todo.
  ip_base = 200

  ips = {
    for indice, nombre in sort(keys(local.servidores)) :
    nombre => cidrhost(data.aws_subnet.elegida.cidr_block, local.ip_base + indice)
  }

  # Direccion de la base de datos que reciben las aplicaciones.
  #
  # Se usa lookup() con valor por defecto en vez de indexar el mapa directo: con
  # enable_rds = true no existe el servidor "data", y un indice a una clave que
  # no existe aborta el plan aunque esa rama no se llegue a usar.
  db_host = var.enable_rds ? aws_db_instance.main[0].address : lookup(
    local.ips, var.topologia == "compacta" ? "app" : "data", ""
  )

  # Direccion de cada plataforma, segun la topologia elegida.
  host_de = {
    for plataforma, _ in local.puertos :
    plataforma => var.topologia == "compacta" ? local.ips["app"] : local.ips[plataforma]
  }

  # Targets que el Prometheus de referencia debe scrapear.
  targets_plataformas = [
    for plataforma, puerto in local.puertos :
    "${local.host_de[plataforma]}:${puerto}"
  ]

  # --- prometheus.yml ---------------------------------------------------------
  # Los bloques de targets se arman ya indentados para que el YAML quede valido
  # (ver infra/monitoring/prometheus.yml.tftpl).
  prom_targets_plataformas = join("\n", [
    for plataforma, puerto in local.puertos :
    "      - targets: [\"${local.host_de[plataforma]}:${puerto}\"]\n        labels:\n          plataforma: \"${plataforma}\""
  ])

  # node_exporter corre como sidecar en TODOS los servidores (puerto 9100).
  prom_targets_nodos = join("\n", [
    for nombre in sort(keys(local.servidores)) :
    "      - targets: [\"${local.ips[nombre]}:9100\"]\n        labels:\n          servidor: \"${nombre}\""
  ])

  # postgres_exporter solo existe cuando la base corre como contenedor (sin RDS).
  prom_postgres_job = var.enable_rds ? "" : join("\n", [
    "  # ------------------------------------------------------------------------",
    "  # 5. postgres_exporter (sidecar junto a PostgreSQL): conexiones, transacciones,",
    "  #    tamano de la base y estado (pg_up).",
    "  # ------------------------------------------------------------------------",
    "  - job_name: \"postgres\"",
    "    static_configs:",
    "      - targets: [\"${local.db_host}:9187\"]",
    "        labels:",
    "          rol: \"base-de-datos\"",
  ])

  prometheus_yml = templatefile("${path.module}/monitoring/prometheus.yml.tftpl", {
    targets_plataformas = local.prom_targets_plataformas
    targets_nodos       = local.prom_targets_nodos
    postgres_job        = local.prom_postgres_job
    borde_ip            = local.ips["borde"]
  })
}
