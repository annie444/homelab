terraform {
  required_version = ">=1.5"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.14.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.31.0"
    }

    sops = {
      source  = "carlpett/sops"
      version = "1.0.0"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = "~/.config/k3s.yaml"
  }
}

provider "kubernetes" {
  config_path    = "~/.config/k3s.yaml"
  config_context = "default"
}


provider "sops" {}
