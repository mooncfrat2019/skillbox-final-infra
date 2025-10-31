terraform {
  required_providers {
    vkcs = {
      source = "vk-cs/vkcs"
      version = "< 1.0.0"
    }
  }
}


provider "vkcs" {
  username = var.username
  password = var.password
  project_id = var.project_id
  region = "RegionOne"
  auth_url = "https://infra.mail.ru:35357/v3/"
}

# Создание сети
resource "vkcs_networking_network" "vm_network" {
  name           = "vm-network"
  admin_state_up = true
}

# Создание подсети
resource "vkcs_networking_subnet" "vm_subnet" {
  name       = "vm-subnet"
  network_id = vkcs_networking_network.vm_network.id
  cidr       = "192.168.199.0/24"
}

# Создание маршрутизатора
resource "vkcs_networking_router" "vm_router" {
  name                = "vm-router"
  admin_state_up      = true
  external_network_id = data.vkcs_networking_network.extnet.id
}


# Привязка маршрутизатора к подсети
resource "vkcs_networking_router_interface" "vm_router_interface" {
  router_id = vkcs_networking_router.vm_router.id
  subnet_id = vkcs_networking_subnet.vm_subnet.id
}

# Получение данных о внешней сети
data "vkcs_networking_network" "extnet" {
  name = "ext-net"
}

data "vkcs_images_image" "compute" {
  visibility = "public"
  default    = true
  properties = {
    mcs_os_distro  = "ubuntu"
    mcs_os_version = "22.04"
  }
}

# Получение данных о флейворе
data "vkcs_compute_flavor" "vm_flavor" {
  name = var.compute_flavor
}

# Создание ВМ
resource "vkcs_compute_instance" "ubuntu_vm" {
  name              = "ubuntu-vm"
  flavor_id         = data.vkcs_compute_flavor.vm_flavor.id
  key_pair          = var.key_pair_name
  security_groups = ["default", "all", "ssh"]
  availability_zone = var.availability_zone_name

  network {
    uuid = vkcs_networking_network.vm_network.id
  }

  block_device {
    uuid                  = data.vkcs_images_image.compute.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = 10
    boot_index            = 0
    delete_on_termination = true
  }
}


# Создание Load Balancer
resource "vkcs_lb_loadbalancer" "lb" {
  name          = "web-lb"
  vip_subnet_id = vkcs_networking_subnet.vm_subnet.id
}

# Создание listener для порта 8080
resource "vkcs_lb_listener" "listener_8080" {
  name            = "listener-8080"
  protocol        = "HTTP"
  protocol_port   = 8080
  loadbalancer_id = vkcs_lb_loadbalancer.lb.id
}

# Создание пула для балансировщика
resource "vkcs_lb_pool" "pool_8080" {
  name        = "pool-8080"
  protocol    = "HTTP"
  lb_method   = "ROUND_ROBIN"
  listener_id = vkcs_lb_listener.listener_8080.id
}

# Добавление ВМ в пул балансировщика
resource "vkcs_lb_member" "vm_member" {
  address       = vkcs_compute_instance.ubuntu_vm.network[0].fixed_ip_v4
  protocol_port = 8080
  pool_id       = vkcs_lb_pool.pool_8080.id
  subnet_id     = vkcs_networking_subnet.vm_subnet.id
}

# Создание монитора здоровья
resource "vkcs_lb_monitor" "health_monitor" {
  name        = "health-monitor"
  pool_id     = vkcs_lb_pool.pool_8080.id
  type        = "HTTP"
  delay       = 20
  timeout     = 10
  max_retries = 3
  url_path    = "/"
}

# Floating IP для Load Balancer
resource "vkcs_networking_floatingip" "lb_fip" {
  pool = "ext-net"
}

# Привязка Floating IP к Load Balancer
resource "vkcs_networking_floatingip_associate" "lb_fip_associate" {
  floating_ip = vkcs_networking_floatingip.lb_fip.address
  port_id     = vkcs_lb_loadbalancer.lb.vip_port_id
}

# Вывод IP-адресов
output "vm_ip" {
  value = vkcs_compute_instance.ubuntu_vm.network[0].fixed_ip_v4
}

output "loadbalancer_ip" {
  value = vkcs_networking_floatingip.lb_fip.address
}

output "loadbalancer_url" {
  value = "http://${vkcs_networking_floatingip.lb_fip.address}:8080"
}