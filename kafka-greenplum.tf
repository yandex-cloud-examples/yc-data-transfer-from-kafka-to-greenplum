# Infrastructure for Yandex Cloud Managed Service for Greenplum® and Managed Service for Apache Kafka®
#
# RU: https://yandex.cloud/ru/docs/data-transfer/tutorials/managed-kafka-to-greenplum
# EN: https://yandex.cloud/en/docs/data-transfer/tutorials/managed-kafka-to-greenplum
#
# Configure the parameters of the source and target clusters:

locals {
  gp_version  = "" # Desired version of Greenplum®. For available versions, see the documentation main page: https://yandex.cloud/en/docs/managed-greenplum/.
  gp_password = "" # Greenplum® admin's password
  kf_version  = "" # Desired version of Apache Kafka®. For available versions, see the documentation main page: https://yandex.cloud/en/docs/managed-kafka/.
  kf_password = "" # Apache Kafka® user's password

  # Specify these settings ONLY AFTER the clusters are created. Then run "terraform apply" command again.
  # You should set up endpoints using the GUI to obtain their IDs
  kf_source_endpoint_id = "" # Set the source endpoint ID
  gp_target_endpoint_id = "" # Set the target endpoint ID
  transfer_enabled      = 0  # Set to 1 to enable the transfer

  # The following settings are predefined. Change them only if necessary.

  # Managed Service for Greenplum®:
  mgp_network_name        = "mgp_network"        # Name of the network for the Greenplum® cluster
  mgp_subnet_name         = "mgp_subnet-a"       # Name of the subnet for the Greenplum® cluster
  mgp_security_group_name = "mgp_security_group" # Name of the security group for the Greenplum® cluster
  gp_cluster_name         = "mgp-cluster"        # Name of the Greenplum® cluster
  gp_username             = "user"               # Username of the Greenplum® cluster

  # Managed Service for Apache Kafka®:
  mkf_network_name        = "mkf_network"        # Name of the network for the Apache Kafka® cluster
  mkf_subnet_name         = "mkf_subnet-a"       # Name of the subnet for the Apache Kafka® cluster
  mkf_security_group_name = "mkf_security_group" # Name of the security group for the Apache Kafka® cluster
  kf_cluster_name         = "mkf-cluster"        # Name of the Apache Kafka® cluster
  kf_topic                = "sensors"            # Name of the Apache Kafka® topic
  kf_username             = "mkf-user"           # Username of the Apache Kafka® cluster

  # Data Transfer:
  transfer_name = "mkf-mgp-transfer" # Name of the transfer from the Managed Service for Apache Kafka® to the Managed Service for Greenplum®
}

# Network infrastructure

resource "yandex_vpc_network" "mgp_network" {
  description = "Network for Managed Service for Greenplum®"
  name        = local.mgp_network_name
}

resource "yandex_vpc_network" "mkf_network" {
  description = "Network for Managed Service for Apache Kafka®"
  name        = local.mkf_network_name
}

resource "yandex_vpc_subnet" "mgp_subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone for Greenplum®"
  name           = local.mgp_subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mgp_network.id
  v4_cidr_blocks = ["10.128.0.0/18"]
}

resource "yandex_vpc_subnet" "mkf_subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone for Apache Kafka®"
  name           = local.mkf_subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mkf_network.id
  v4_cidr_blocks = ["10.129.0.0/24"]
}

resource "yandex_vpc_security_group" "mgp_security_group" {
  description = "Security group for Managed Service for Greenplum®"
  network_id  = yandex_vpc_network.mgp_network.id
  name        = local.mgp_security_group_name

  ingress {
    description    = "Allow incoming traffic from the Internet"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing traffic to the Internet"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "mkf_security_group" {
  description = "Security group for Managed Service for Apache Kafka®"
  network_id  = yandex_vpc_network.mkf_network.id
  name        = local.mkf_security_group_name

  ingress {
    description    = "Allow incoming traffic from the port 9091"
    protocol       = "TCP"
    port           = 9091
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing traffic to the Internet"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Infrastructure for the Managed Service for Greenplum® cluster

resource "yandex_mdb_greenplum_cluster" "mgp-cluster" {
  description        = "Managed Service for Greenplum® cluster"
  name               = local.gp_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.mgp_network.id
  zone               = "ru-central1-a"
  subnet_id          = yandex_vpc_subnet.mgp_subnet-a.id
  assign_public_ip   = true
  version            = local.gp_version
  master_host_count  = 2
  segment_host_count = 2
  segment_in_host    = 1
  master_subcluster {
    resources {
      resource_preset_id = "s2.medium" # 8 vCPU, 32 GB RAM
      disk_size          = 100         #GB
      disk_type_id       = "local-ssd"
    }
  }
  segment_subcluster {
    resources {
      resource_preset_id = "s2.medium" # 8 vCPU, 32 GB RAM
      disk_size          = 100         # GB
      disk_type_id       = "local-ssd"
    }
  }

  user_name     = local.gp_username
  user_password = local.gp_password

  security_group_ids = [yandex_vpc_security_group.mgp_security_group.id]
}

# Infrastructure for the Managed Service for Apache Kafka® cluster

resource "yandex_mdb_kafka_cluster" "mkf-cluster" {
  description        = "Managed Service for Apache Kafka® cluster"
  environment        = "PRODUCTION"
  name               = local.kf_cluster_name
  network_id         = yandex_vpc_network.mkf_network.id
  security_group_ids = [yandex_vpc_security_group.mkf_security_group.id]

  config {
    assign_public_ip = true
    brokers_count    = 1
    version          = local.kf_version
    kafka {
      resources {
        disk_size          = 10 # GB
        disk_type_id       = "network-ssd"
        resource_preset_id = "s2.micro"
      }
    }

    zones = [
      "ru-central1-a"
    ]
  }

  depends_on = [
    yandex_vpc_subnet.mkf_subnet-a
  ]
}

# Topic of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_topic" "sensors" {
  cluster_id         = yandex_mdb_kafka_cluster.mkf-cluster.id
  name               = local.kf_topic
  partitions         = 1
  replication_factor = 1
}

# User of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_user" "mkf-user" {
  cluster_id = yandex_mdb_kafka_cluster.mkf-cluster.id
  name       = local.kf_username
  password   = local.kf_password
  permission {
    topic_name = yandex_mdb_kafka_topic.sensors.name
    role       = "ACCESS_ROLE_CONSUMER"
  }
  permission {
    topic_name = yandex_mdb_kafka_topic.sensors.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

# Data Transfer infrastructure

resource "yandex_datatransfer_transfer" "mkf-mgp-transfer" {
  description = "Transfer from the Managed Service for Apache Kafka® to the Managed Service for Greenplum®"
  count       = local.transfer_enabled
  name        = local.transfer_name
  source_id   = local.kf_source_endpoint_id
  target_id   = local.gp_target_endpoint_id
  type        = "INCREMENT_ONLY" # Data replication from the source Managed Service for Apache Kafka® topic to the target Managed Service for Greenplum® cluster
}
