terraform {
  required_version = ">= 1.6"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

variable "mq_image" {
  type    = string
  default = "icr.io/ibm-messaging/mq@sha256:2cb02e7991ac9fc44d10ba4e353abdc1402ec1667243b74a4574df5f274d7907"
}

variable "mq_app_password" {
  type      = string
  sensitive = true
}

variable "mq_admin_password" {
  type      = string
  sensitive = true
}

variable "porta_listener" {
  type    = number
  default = 1415
}

variable "porta_console" {
  type    = number
  default = 9444
}

resource "docker_image" "mq" {
  name         = var.mq_image
  keep_locally = true
}

resource "docker_volume" "dados" {
  name = "mqdata-tf"
}

resource "docker_container" "qm" {
  name   = "qm1-tf"
  image  = docker_image.mq.image_id
  memory = 1024

  env = [
    "LICENSE=accept",
    "MQ_QMGR_NAME=QM1",
    "MQ_APP_PASSWORD=${var.mq_app_password}",
    "MQ_ADMIN_PASSWORD=${var.mq_admin_password}",
  ]

  ports {
    internal = 1414
    external = var.porta_listener
  }

  ports {
    internal = 9443
    external = var.porta_console
  }

  volumes {
    volume_name    = docker_volume.dados.name
    container_path = "/mnt/mqm"
  }
}

output "container" {
  value = docker_container.qm.name
}
