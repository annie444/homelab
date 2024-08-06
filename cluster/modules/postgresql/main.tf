resource "kubernetes_namespace" "postgresql" {
  metadata {
    annotations = {
      name = "postgresql"
    }
    name = "postgresql"
  }
}

data "sops_file" "postgres" {
  source_file = "${path.module}/secrets/postgresql.yaml"
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
    export PGPASSWORD='${data.sops_file.postgres.data["postgres-password"]}'
    psql -U postgres -h localhost -c "CREATE USER matrix_media_repo WITH NOSUPERUSER CREATEDB NOCREATEROLE NOINHERIT LOGIN NOREPLICATION NOBYPASSRLS ENCRYPTED PASSWORD '${data.sops_file.postgres.data["media-password"]}';"
    psql -U postgres -h localhost -c "CREATE DATABASE matrix_media_repo WITH OWNER = 'matrix_media_repo';"
    psql -U postgres -h localhost -c "CREATE USER sliding_sync WITH NOSUPERUSER CREATEDB NOCREATEROLE NOINHERIT LOGIN NOREPLICATION NOBYPASSRLS ENCRYPTED PASSWORD '${data.sops_file.postgres.data["sync-password"]}';"
    psql -U postgres -h localhost -c "CREATE DATABASE sliding_sync WITH OWNER = 'sliding_sync';"

    EO_SCRIPT
  }

  type = "Opaque"
}

resource "helm_release" "postgresql" {
  name       = "postgresql"
  namespace  = kubernetes_namespace.postgresql.metadata[0].name
  chart      = "postgresql"
  repository = "https://charts.bitnami.com/bitnami"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = concat(
    [file("${path.module}/values/postgresql.values.yaml")],
    (
      var.monitoring ?
      [file("${path.module}/values/postgresql.monitoring.yaml")] :
      [file("${path.module}/values/postgresql.no-monitoring.yaml")]
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

data "kubernetes_service_v1" "postgresql" {
  metadata {
    name      = helm_release.postgresql.name
    namespace = helm_release.postgresql.namespace
    labels = {
      "app.kubernetes.io/component" = "primary"
    }
  }
}
