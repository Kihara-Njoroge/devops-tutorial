terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.18.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config" # Path to your Kubernetes config file
}

# Create the namespace
resource "kubernetes_namespace" "test_app" {
  metadata {
    name = "test-app"
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

# Create persistent volume claim for MongoDB
resource "kubernetes_persistent_volume_claim" "mongo_pvc" {
  metadata {
    name      = "mongo-pvc"
    namespace = kubernetes_namespace.test_app.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

# Deploy frontend
resource "kubernetes_deployment" "frontend" {
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.test_app.metadata[0].name
    labels = {
      app = "frontend"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "frontend"
      }
    }
    template {
      metadata {
        labels = {
          app = "frontend"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "80"
        }
      }
      spec {
        container {
          name              = "frontend"
          image             = "test-app/frontend:latest"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 80
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "256Mi"
            }
          }
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend_service" {
  metadata {
    name      = "frontend-service"
    namespace = kubernetes_namespace.test_app.metadata[0].name
    labels = {
      app = "frontend"
    }
  }
  spec {
    selector = {
      app = "frontend"
    }
    port {
      port        = 80
      target_port = 80
      name        = "http"
    }
    type = "ClusterIP"
  }
}

# Deploy backend
resource "kubernetes_deployment" "backend" {
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace.test_app.metadata[0].name
    labels = {
      app = "backend"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "backend"
      }
    }
    template {
      metadata {
        labels = {
          app = "backend"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "3000"
          "prometheus.io/path"   = "/metrics"
        }
      }
      spec {
        container {
          name              = "backend"
          image             = "test-app/backend:latest"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 3000
          }
          env {
            name  = "MONGO_URI"
            value = "mongodb://database-service:27017/testapp"
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "256Mi"
            }
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
          volume_mount {
            name       = "app-logs"
            mount_path = "/var/log/app"
          }
        }
        volume {
          name = "app-logs"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "backend_service" {
  metadata {
    name      = "backend-service"
    namespace = kubernetes_namespace.test_app.metadata[0].name
    labels = {
      app = "backend"
    }
  }
  spec {
    selector = {
      app = "backend"
    }
    port {
      port        = 3000
      target_port = 3000
      name        = "http"
    }
    type = "ClusterIP"
  }
}

# Deploy database
resource "kubernetes_deployment" "database" {
  metadata {
    name      = "database"
    namespace = kubernetes_namespace.test_app.metadata[0].name
    labels = {
      app = "database"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "database"
      }
    }
    template {
      metadata {
        labels = {
          app = "database"
        }
      }
      spec {
        container {
          name              = "mongodb"
          image             = "test-app/database:latest"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 27017
          }
          resources {
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
          volume_mount {
            name       = "mongo-data"
            mount_path = "/data/db"
          }
        }
        volume {
          name = "mongo-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.mongo_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "database_service" {
  metadata {
    name      = "database-service"
    namespace = kubernetes_namespace.test_app.metadata[0].name
    labels = {
      app = "database"
    }
  }
  spec {
    selector = {
      app = "database"
    }
    port {
      port        = 27017
      target_port = 27017
      name        = "mongo"
    }
    type = "ClusterIP"
  }
}

# Create Istio Gateway
resource "kubernetes_manifest" "gateway" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "Gateway"
    metadata = {
      name      = "test-app-gateway"
      namespace = kubernetes_namespace.test_app.metadata[0].name
    }
    spec = {
      selector = {
        istio = "ingressgateway"
      }
      servers = [
        {
          port = {
            number   = 80
            name     = "http"
            protocol = "HTTP"
          }
          hosts = ["*"]
        }
      ]
    }
  }
  depends_on = [kubernetes_namespace.test_app]
}

# Create VirtualService for frontend
resource "kubernetes_manifest" "frontend_vs" {
  manifest = {
    apiVersion = "networking.istio.io/v1alpha3"
    kind       = "VirtualService"
    metadata = {
      name      = "frontend-vs"
      namespace = kubernetes_namespace.test_app.metadata[0].name
    }
    spec = {
      hosts    = ["*"]
      gateways = ["test-app-gateway"]
      http = [
        {
          match = [
            {
              uri = {
                prefix = "/"
              }
            }
          ]
          route = [
            {
              destination = {
                host = "frontend-service"
                port = {
                  number = 80
                }
              }
            }
          ]
        }
      ]
    }
  }
  depends_on = [kubernetes_manifest.gateway, kubernetes_service.frontend_service]
}
