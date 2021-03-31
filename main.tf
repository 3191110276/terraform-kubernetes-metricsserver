############################################################
# REQUIRED PROVIDERS
############################################################
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.2"
    }
  }
}


############################################################
# INSTALL METRICS SERVER
############################################################
resource "kubernetes_service_account" "metrics-server" {
  metadata {
    name      = "metrics-server"
    namespace = "kube-system"
    
    labels = {
      "k8s-app" = "metrics-server"
    }
  }
}

resource "kubernetes_cluster_role" "aggregated-metrics-reader" {
  metadata {
    name = "system:aggregated-metrics-reader"
    
    labels = {
      "k8s-app" = "metrics-server"
      
      "rbac.authorization.k8s.io/aggregate-to-admin" = "true"
      "rbac.authorization.k8s.io/aggregate-to-edit" = "true"
      "rbac.authorization.k8s.io/aggregate-to-view" = "true"
    }
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["pods", "nodes"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role" "metrics-server" {
  metadata {
    name = "system:metrics-server"
    
    labels = {
      "k8s-app" = "metrics-server"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "nodes", "nodes/stats", "namespaces", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding" "metrics-server-auth-reader" {
  metadata {
    name      = "metrics-server-auth-reader"
    namespace = "kube-system"
    
    labels = {
      "k8s-app" = "metrics-server"
    }
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "extension-apiserver-authentication-reader"
  }
  
  subject {
    kind      = "ServiceAccount"
    name      = "metrics-server"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding" "auth-delegator" {
  metadata {
    name = "metrics-server:system:auth-delegator"
    
    labels = {
      "k8s-app" = "metrics-server"
    }
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "metrics-server"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding" "metrics-server" {
  metadata {
    name = "system:metrics-server"
    
    labels = {
      "k8s-app" = "metrics-server"
    }
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:metrics-server"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "metrics-server"
    namespace = "kube-system"
  }
}

resource "kubernetes_service" "metrics-server" {
  metadata {
    name = "metrics-server"
    namespace = "kube-system"
    
    labels = {
      "k8s-app" = "metrics-server"
    }
  }
  
  spec {
    selector = {
      "k8s-app" = "metrics-server"
    }
    session_affinity = "ClientIP"
    port {
      name        = "https"
      port        = 443
      protocol    = "TCP"
      target_port = 443
    }
  }
}

resource "kubernetes_deployment" "example" {
  metadata {
    name      = "metrics-server"
    namespace = "kube-system"
    
    labels = {
      "k8s-app" = "metrics-server"
    }
  }

  spec {
    replicas = 1
    
    strategy {
      type = "RollingUpdate"
      rolling_update = {
        max_unavailable = 0
      }
    }

    selector {
      match_labels = {
        "k8s-app" = "metrics-server"
      }
    }

    template {
      metadata {
        labels = {
          "k8s-app" = "metrics-server"
        }
      }

      spec {
        container {
          name = "metrics-server"
          
          image             = "k8s.gcr.io/metrics-server/metrics-server:v0.4.2"
          image_pull_policy = "IfNotPresent"
          
          args = ["--cert-dir=/tmp", "--secure-port=4443", "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname", "--kubelet-use-node-status-port"]
          
          port {
            name           = "https"
            container_port = 4443
            protocol       = "TCP"
          }
          
          volume_mount {
            name = "tmp-dir"
            mount_path = "tmp-dir"
          }
          
          security_context {
            read_only_root_filesystem = true
            run_as_non_root           = true
            run_as_user               = 1000
          }
        }
        
        liveness_probe = {
            http_get {
              path   = "/livez"
              port   = 443
              scheme = "HTTPS"
            }

            period_seconds    = 10
            failure_threshold = 3
        }
        
        readiness_probe = {
            http_get {
              path   = "/readyz"
              port   = 443
              scheme = "HTTPS"
            }

            period_seconds    = 10
            failure_threshold = 3
        }
        
        node_selector = {
          "kubernetes.io/os" = "linux"
        }
        
        priority_class_name = "system-cluster-critical"
        
        service_account_name = "metrics-server"
        
        volume {
          name      = "tmp-dir"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_api_service" "metrics-server" {
  metadata {
    name = "v1beta1.metrics.k8s.io"
    
    labels = {
      "k8s-app" = "metrics-server"
    }
  }
 
  spec {
    group                  = "metrics.k8s.io"
    group_priority_minimum = 100
    
    insecure_skip_tls_verify = true
    
    service {
      name = "metrics-server"
      namespace = "kube-system"
    }
    
    version          = "v1beta1"
    version_priority = 100
  }
}
