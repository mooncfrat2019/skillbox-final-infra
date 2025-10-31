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


data "vkcs_compute_flavor" "compute" {
  name = var.compute_flavor
}

data "vkcs_images_image" "compute" {
  visibility = "public"
  default    = true
  properties = {
    mcs_os_distro  = "ubuntu"
    mcs_os_version = "22.04"
  }
}

resource "vkcs_compute_instance" "metrics" {
  name                    = "${var.instance_name}-metrics-prod"
  flavor_id               = data.vkcs_compute_flavor.compute.id
  key_pair                = var.key_pair_name
  security_groups         = ["default","ssh", "all"]
  availability_zone       = var.availability_zone_name

  block_device {
    uuid                  = data.vkcs_images_image.compute.id
    source_type           = "image"
    destination_type      = "volume"
    volume_type           = "ceph-ssd"
    volume_size           = 20
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    uuid = data.vkcs_networking_network.vm-network.id
  }
}


resource "vkcs_networking_floatingip" "runner_fip" {
  pool = var.external_network_name
}

resource "vkcs_compute_floatingip_associate" "runner_fip" {
  floating_ip = vkcs_networking_floatingip.runner_fip.address
  instance_id = vkcs_compute_instance.metrics.id
}