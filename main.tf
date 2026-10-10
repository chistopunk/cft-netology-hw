terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

provider "yandex" {
  token     = "t1.secret"
  cloud_id  = "b1gkjakgtanqejlkpmqd"
  folder_id = "b1g1jhiv5jpbhu7vs7h7"
  zone      = "ru-central1-e"
}

resource "yandex_vpc_network" "my_network" {
  name = "hw-network"
}

resource "yandex_vpc_subnet" "my_subnet" {
  name           = "hw-subnet"
  zone           = "ru-central1-e"
  network_id     = yandex_vpc_network.my_network.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_compute_instance" "web" {
  count = 2
  name  = "web-server-${count.index + 1}"
  platform_id = "standard-v3"

  allow_stopping_for_update = true

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  scheduling_policy {
    preemptible = true
  }

  boot_disk {
    initialize_params {
      image_id = "fd8snjpoq85qqv0mk9gi" 
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.my_subnet.id
    nat       = true
  }

  metadata = {
    user-data = <<-EOF
      #!/bin/bash
      apt-get update
      apt-get install -y nginx
      systemctl enable nginx
      systemctl start nginx
    EOF
  }
}

  name = "hw-target-group"

  target {
    subnet_id = yandex_vpc_subnet.my_subnet.id
    address   = yandex_compute_instance.web[0].network_interface.0.ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.my_subnet.id
    address   = yandex_compute_instance.web[1].network_interface.0.ip_address
  }
}

resource "yandex_lb_network_load_balancer" "my_lb" {
  name = "hw-load-balancer"

  listener {
    name = "http-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.my_target_group.id
    healthcheck {
      name = "http-healthcheck"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

output "load_balancer_ip" {
  value = yandex_lb_network_load_balancer.my_lb.listener.*.external_address_spec[0].*.address
}