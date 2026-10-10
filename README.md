# Домашнее задание к занятию "`Отказоустойчивость в облаке`" - `Чередниченко Владислав

### Задание 1

В ходе выполнения задания была подготовлена инфраструктура в Yandex Cloud с помощью Terraform: развернуты две виртуальные машины с веб-сервером Nginx, объединенные в целевую группу, и настроен сетевой балансировщик нагрузки.

1\. Установлена утилита `yc`, получен токен для авторизации Terraform в Yandex Cloud. Установлен Terraform.
2\. Подготовлен конфигурационный файл `main.tf`, описывающий создание VPC, подсети, виртуальных машин, целевой группы и сетевого балансировщика.
3\. Для создания идентичных ВМ использован аргумент `count = 2`. Настройка Nginx выполнена автоматически при запуске машин с помощью cloud-init (через блок `user-data`).
4\. Для обхода ограничений квот нового аккаунта применены настройки: платформа `standard-v3`, `core_fraction = 20` и политика прерываемости (`preemptible = true`).
5\. Выполнено развертывание инфраструктуры командами `terraform init` и `terraform apply`.
6\. Выполнена проверка работоспособности: балансировщик активен, хосты в статусе healthy, при обращении по внешнему IP открывается дефолтная страница Nginx. 

``` hcl
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

provider "yandex" {
  token     = "ТВОЙ_ТОКЕН"
  cloud_id  = "b1gkjakgtanqejlkpmqd"
  folder_id = "b1g1jhiv5jpbhu7vs7h7"
  zone      = "ru-central1-e"
}

# 1. Создаем сеть и подсеть
resource "yandex_vpc_network" "my_network" {
  name = "hw-network"
}

resource "yandex_vpc_subnet" "my_subnet" {
  name           = "hw-subnet"
  zone           = "ru-central1-e"
  network_id     = yandex_vpc_network.my_network.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

# 2. Создаем 2 идентичные виртуальные машины
resource "yandex_compute_instance" "web" {
  count       = 2
  name        = "web-server-${count.index + 1}"
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
      # Образ Ubuntu 20.04
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

# 3. Создаем таргет-группу
resource "yandex_lb_target_group" "my_target_group" {
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

# 4. Создаем балансировщик нагрузки
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

# 5. Вывод IP балансировщика
output "load_balancer_ip" {
  value = yandex_lb_network_load_balancer.my_lb.listener.*.external_address_spec[0].*.address
}
```
<img width="1449" height="366" alt="task-1_nginx_page" src="https://github.com/user-attachments/assets/2ef50726-2608-4775-826f-2498c4101bd0" />

<img width="633" height="1158" alt="task-1_balancer" src="https://github.com/user-attachments/assets/efd9aa2f-1589-463d-93ad-994aa6a05282" />
