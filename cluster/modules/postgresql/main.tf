resource "kubernetes_namespace" "postgresql" {
  metadata {
    annotations = {
      name = "postgresql"
    }
    name = "postgresql"
  }
}

data "sops_file" "postgres" {
  source_file = "./secrets/postgresql.yaml"
}

resource "kubernetes_secret" "postgresql" {
  metadata {
    name      = "postgresql-secret"
    namespace = kubernetes_namespace.postgresql.metadata[0].name
  }

  data = {
    "postgres-password"    = data.sops_file.postgres.data["postgres-password"]
    "password"             = data.sops_file.postgres.data["password"]
    "replication-password" = data.sops_file.postgres.data["replication-password"]
  }

  type = "Opaque"
}

resource "kubernetes_secret" "postgresql_init" {
  metadata {
    name      = "postgresql-init"
    namespace = kubernetes_namespace.postgresql.metadata[0].name
  }

  data = {
    "init.sh" = <<-EO_SCRIPT
    #!/bin/sh
    psql postgresql://postgres:${data.sops_file.postgres.data["postgres-password"]}@localhost:5433/?sslmode=disable << E_O_SQL
    CREATE USER matrix_media_repo WITH NOSUPERUSER CREATEDB NOCREATEROLE NOINHERIT LOGIN NOREPLICATION NOBYPASSRLS ENCRYPTED PASSWORD '${data.sops_file.postgres.data["media-password"]}';
    CREATE DATABASE matrix_media_repo WITH OWNER = 'matrix_media_repo';
    E_O_SQL

    EO_SCRIPT
  }

  type = "Opaque"
}

resource "helm_release" "postgresql" {
  name       = "postgresql"
  namespace  = kubernetes_namespace.postgresql.metadata[0].name
  chart      = "postgresql"
  version    = "15.5.20"
  repository = "https://charts.bitnami.com/bitnami"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = concat(
    [file("./values/postgresql.values.yaml")],
    (
      var.monitoring ?
      [file("./values/postgresql.monitoring.values.yaml")] :
      [file("./values/postgresql.no-monitoring.values.yaml")]
    )
  )

  set {
    name  = "auth.existingSecret"
    value = kubernetes_secret.postgresql.metadata[0].name
  }

  set {
    name  = "global.postgresql.auth.existingSecret"
    value = kubernetes_secret.postgresql.metadata[0].name
  }

  set {
    name  = "primary.initdb.scriptsSecret"
    value = kubernetes_secret.postgresql_init.metadata[0].name
  }

  set {
    name  = "global.defaultStorageClass"
    value = var.storage_class
  }
}

data "kubernetes_service" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = helm_release.postgresql.namespace
    labels = {
      "app.kubernetes.io/component" = "primary"
    }
  }
}
