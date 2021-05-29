# OpenStack 

<!-- sudo sudo timedatectl set-timezone Europe/London
sudo timedatectl set-ntp on -->

## Types of Network Traffic 

### Management 

Used for internal communication between hosts for services, such as the messaging and database services. 

### API 

Used to expose OpenStack APIs to users of the cloud and services within the cloud. Endpoint addresses for services, such as Keystone, Neutron, Glance, and Horizon, are procured from the API network.

### External 

Provides Neutron routers with network access. Once a router has been configured, this network becomes the source of floating IP addresses for instances and load balancer VIPs. IP addresses in this network should be reachable by any client on the Internet.

### Guest

A network dedicated to instance traffic. Options for guest networks include local networks restricted to a particular node, flat or VLAN tagged networks, or the use of virtual overlay networks made possible with GRE or VXLAN encapsulation.

## Network namespaces 

Multitenancy is supported through the use of network namespace isolation. Each tenant to have multiple private networks, routers, firewalls, and load balancers.

Naming convention for network namespaces:

- qdhcp-<network UUID>
  The qdhcp namespace contains a DHCP service that provides IP addresses to instances using the DHCP protocol. The qdhcp namespace has an interface plugged into the virtual switch and is able to communicate with other resources in the same network or subnet.

- qrouter-<router UUID>
  The qrouter namespace represents a router and routes traffic for instances in subnets that it is connected to. Like the qdhcp namespace, the qrouter namespace is connected to one or more virtual switches, depending on the configuration.

- qlbaas-<load balancer UUID>
  The qlbaas namespace represents a load balancer and might contain a load-balancing service, such as HAProxy, which load balances traffic to instances. The qlbaas namespace is connected to a virtual switch and can communicate with other resources in the same network or subnet.

The ip netns command can be used to list the available namespaces, and commands can be executed within the namespace using the following syntax:
```
ip netns exec NAME <command>
```

## DNS Hosts 

Run on both nodes to provide DNS resolution of hostnames

```bash
# Controller node 
sudo sed -i '/^127.0.0.1 localhost.*/a 10.40.1.6 controller1' /etc/hosts
# Compute node 
sudo sed -i '/^127.0.0.1 localhost.*/a 10.40.1.8 compute1' /etc/hosts
```

## Network Time Protocl (NTP) 

To properly synchronize services among nodes using Chrony, an implementation of NTP. Configure the controller node to reference more accurate (lower stratum) servers and other nodes to reference the controller node

Control Node: 

```bash 
export NODE_SUBNET=10.40.1.0/24

sudo apt install -y chrony
# Possible to reference more accurate NTP servers with line 'server NTP_SERVER iburst'
sudo sed -i -e '$a #Permit Node Connections\nallow '"$NODE_SUBNET"'' /etc/chrony/chrony.conf
sudo service chrony restart
```

Compute Node: 
```bash 
sudo apt install -y chrony
sudo sed -i -e '$a #Source Server\nserver controller1 iburst' /etc/chrony/chrony.conf
sudo sed -e '/pool.*/s/^/#/g' -i /etc/chrony/chrony.conf
sudo service chrony restart
```

Verify:
```bash 
chronyc sources
```

## Ubuntu OpenStack packages 

<https://docs.openstack.org/install-guide/environment-packages-ubuntu.html#finalize-the-installation>

Controller & Compute Node:

```bash 
sudo add-apt-repository -y cloud-archive:wallaby
sudo apt dist-upgrade -y 
sudo apt update
```

## OpenStack Client 

```bash
sudo apt install -y python3-openstackclient
```

## SQL Database 

Most OpenStack services use an SQL database to store information. The database typically runs on the controller node.

<https://docs.openstack.org/install-guide/environment-sql-database-ubuntu.html>

Controller:

```bash 
export CONTROLLER_MGMT_IPADDR=10.40.1.6 # management ip address of controller node
export MYSQL_ROOT_PASSWORD=ved

sudo apt install -y mariadb-server python3-pymysql 
sudo touch /etc/mysql/mariadb.conf.d/99-openstack.cnf

echo "
[mysqld]
bind-address = $CONTROLLER_MGMT_IPADDR

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
" | sudo tee -a /etc/mysql/mariadb.conf.d/99-openstack.cnf > /dev/null 

sudo service mysql restart

# Enter current password for root (ved)
sudo mysql_secure_installation 
```

## Message Queue 

Message queue to coordinate operations and status information among services. The message queue service typically runs on the controller node

<https://docs.openstack.org/install-guide/environment-messaging-ubuntu.html>

Controller: 

```bash 
export RABBIT_PASS=ved

sudo apt install -y rabbitmq-server
sudo rabbitmqctl add_user openstack $RABBIT_PASS
sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*"
```

## Memcached (Token Caching) 

The Identity service authentication mechanism for services uses Memcached to cache tokens. The memcached service typically runs on the controller node. 

*** For production deployments, we recommend enabling a combination of firewalling, authentication, and encryption to secure it.

<https://docs.openstack.org/install-guide/environment-memcached-ubuntu.html>

Controller: 

```bash 
export CONTROLLER_MGMT_IPADDR=10.40.1.6 # management ip address of controller node

sudo apt install -y memcached libmemcached-tools
sudo sed -i 's/-l 127.0.0.1.*/-l '"$CONTROLLER_MGMT_IPADDR"'/' /etc/memcached.conf
sudo service memcached restart
```

## ETCD 

OpenStack services may use Etcd, a distributed reliable key-value store for distributed key locking, storing configuration, keeping track of service live-ness and other scenarios.

```bash
export CONTROLLER_MGMT_IPADDR=10.40.1.6 # management ip address of controller node

sudo apt install -y etcd

echo "
ETCD_NAME="controller1"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER="controller1=http://$CONTROLLER_MGMT_IPADDR:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://$CONTROLLER_MGMT_IPADDR:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://$CONTROLLER_MGMT_IPADDR:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://$CONTROLLER_MGMT_IPADDR:2379"
" | sudo tee -a /etc/default/etcd > /dev/null 

sudo systemctl enable etcd
sudo systemctl restart etcd
```

## Keystone 

The OpenStack Identity service provides a single point of integration for managing authentication, authorization, and a catalog of services.

*** For simplicity, this guide uses the management network for all endpoint types and the default RegionOne region

<https://docs.openstack.org/keystone/latest/install/index-ubuntu.html>

Controller: 

```bash 
export DBPASS=ved
export KEYSTONE_DBPASS=ved
export ADMIN_PASS=ved

sudo mysql -u root -p$DBPASS -e "CREATE DATABASE keystone"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "SHOW GRANTS FOR keystone"

sudo apt install -y keystone

# To reinstall if config files previously purged 
sudo apt install --reinstall -o Dpkg::Options::="--force-confask,confnew,confmiss" keystone
sudo apt install --reinstall -o Dpkg::Options::="--force-confask,confnew,confmiss" $(dpkg -S /etc/keystone | sed 's/,//g; s/:.*//')

sudo sed -i 's/connection = sqlite:\/\/\/\/var\/lib\/keystone\/keystone.db.*/connection = mysql+pymysql:\/\/keystone:'"$KEYSTONE_DBPASS"'@controller1\/keystone/' /etc/keystone/keystone.conf

sudo sed -i 's/#provider = fernet.*/provider = fernet/' /etc/keystone/keystone.conf

sudo -H -u keystone /bin/sh -c "keystone-manage db_sync" 

sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

sudo keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

sudo keystone-manage bootstrap --bootstrap-password "$ADMIN_PASS" \
  --bootstrap-admin-url http://controller1:35357/v3/ \
  --bootstrap-internal-url http://controller1:5000/v3/ \
  --bootstrap-public-url http://controller1:5000/v3/ \
  --bootstrap-region-id RegionOne

sudo sed -i -e '$aServerName controller1' /etc/apache2/apache2.conf

sudo service apache2 restart

export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller1:5000/v3
export OS_IDENTITY_API_VERSION=3

openstack domain create --description "Domain 1" domain1

openstack project create --domain default --description "Service Project" service

openstack --os-auth-url http://controller1:5000/v3   --os-project-domain-name Default --os-user-domain-name Default   --os-project-name admin --os-username admin token issue

echo "
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://controller1:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
" | sudo tee -a ~/admin-openrc > /dev/null 

. admin-openrc
openstack token issue
```

## Glance 

Image service (glance) enables users to discover, register, and retrieve virtual machine images. It offers a REST API that enables you to query virtual machine image metadata and retrieve an actual image. You can store virtual machine images made available through the Image service in a variety of locations, from simple file systems to object-storage systems like OpenStack Object Storage.

*** For simplicity, this guide describes configuring the Image service to use the file back end, which uploads and stores in a directory on the controller node hosting the Image service. By default, this directory is /var/lib/glance/images/.

<https://docs.openstack.org/glance/wallaby/install/install-ubuntu.html>

Controller: 

```bash 
export DBPASS=ved
export GLANCE_DBPASS=ved
export GLANCE_PASS=ved

sudo mysql -u root -p$DBPASS -e "CREATE DATABASE glance"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '${GLANCE_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '${GLANCE_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "SHOW GRANTS FOR glance"

. admin-openrc

openstack user create --domain default --password $GLANCE_PASS glance

openstack role add --project service --user glance admin

openstack service create --name glance --description "OpenStack Image" image

openstack endpoint create --region RegionOne image public http://controller1:9292

openstack endpoint create --region RegionOne image internal http://controller1:9292

openstack endpoint create --region RegionOne image admin http://controller1:9292

sudo apt install -y glance

# To reinstall if config files previously purged 
sudo apt install --reinstall -o Dpkg::Options::="--force-confask,confnew,confmiss" glance
sudo apt install --reinstall -o Dpkg::Options::="--force-confask,confnew,confmiss" $(dpkg -S /etc/glance | sed 's/,//g; s/:.*//')

sudo sed -i 's/connection = sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite.*/connection = mysql+pymysql:\/\/glance:'"$GLANCE_DBPASS"'@controller1\/glance/' /etc/glance/glance-api.conf

sudo sed -i 's/^\[keystone_authtoken\].*/\[keystone_authtoken\] \
www_authenticate_uri = http:\/\/controller1:5000 \
auth_url = http:\/\/controller1:5000 \
memcached_servers = controller1:11211 \
auth_type = password \
project_domain_name = Default \
user_domain_name = Default \
project_name = service \
username = glance \
password = '"$GLANCE_PASS"' \
  /' /etc/glance/glance-api.conf

sudo sed -i 's/^\[paste_deploy\].*/\[paste_deploy\] \
flavor = keystone/' /etc/glance/glance-api.conf

sudo sed -i 's/^\[glance_store\].*/\[glance_store\] \
stores = file,http \
default_store = file \
filesystem_store_datadir = \/var\/lib\/glance\/images\/ \
  /' /etc/glance/glance-api.conf

sudo -H -u glance /bin/sh -c "glance-manage db_sync" 

sudo service glance-api restart

. admin-openrc

wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img

glance image-create --name "cirros" \
  --file cirros-0.4.0-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --visibility=public

glance image-list
```

## Placement 

Placement provides a placement-api WSGI script for running the service with Apache, nginx or other WSGI-capable web servers. Depending on what packaging solution is used to deploy OpenStack, the WSGI script may be in /usr/bin or /usr/local/bin.

*** use an endpoint URL of http://controller1:8778/ as an example only. You should configure placement to use whatever hostname and port works best for your environment. Using SSL on the default port, with either a domain or path specific to placement, is recommended. For example: https://mygreatcloud.com/placement or https://placement.mygreatcloud.com/.

<https://docs.openstack.org/placement/wallaby/install/install-ubuntu.html>

Controller: 

```bash 
export DBPASS=ved
export PLACEMENT_DBPASS=ved
export PLACEMENT_PASS=ved

sudo mysql -u root -p$DBPASS -e "CREATE DATABASE placement"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '${PLACEMENT_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '${PLACEMENT_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "SHOW GRANTS FOR placement"

. admin-openrc

openstack user create --domain default --password $PLACEMENT_PASS placement

openstack role add --project service --user placement admin

openstack service create --name placement --description "Placement API" placement

openstack endpoint create --region RegionOne placement public http://controller1:8778

openstack endpoint create --region RegionOne placement internal http://controller1:8778

openstack endpoint create --region RegionOne placement admin http://controller1:8778

sudo apt install -y placement-api

sudo cp /etc/placement/placement.conf /etc/placement/placement.conf.bak 

sudo sed -i 's/connection = sqlite:\/\/\/\/var\/lib\/placement\/placement.sqlite.*/connection = mysql+pymysql:\/\/placement:'"$PLACEMENT_DBPASS"'@controller1\/placement/' /etc/placement/placement.conf

sudo sed -i 's/^\[api\].*/\[api\] \
auth_strategy = keystone/' /etc/placement/placement.conf

sudo sed -i 's/^\[keystone_authtoken\].*/\[keystone_authtoken\] \
auth_url = http:\/\/controller1:5000\/v3 \
memcached_servers = controller1:11211 \
auth_type = password \
project_domain_name = Default \
user_domain_name = Default \
project_name = service \
username = placement \
password = '"$PLACEMENT_DBPASS"' \
  /' /etc/placement/placement.conf

sudo -H -u placement /bin/sh -c "placement-manage db sync" 

sudo service apache2 restart 

. admin-openrc

sudo placement-status upgrade check

sudo apt install -y python3-pip
pip3 install osc-placement
```

## Nova - Controller Node 

OpenStack Compute interacts with OpenStack Identity for authentication, OpenStack Placement for resource inventory tracking and selection, OpenStack Image service for disk and server images, and OpenStack Dashboard for the user and administrative interface. Image access is limited by projects, and by users; quotas are limited per project (the number of instances, for example). OpenStack Compute can scale horizontally on standard hardware, and download images to launch instances.

Controller: 

```bash 
export DBPASS=ved
export NOVA_DBPASS=ved
export NOVA_PASS=ved
export RABBIT_PASS=ved
export CONTROLLER_MGMT_IPADDR=10.40.1.6 # management ip address of controller node
export PLACEMENT_PASS=ved

sudo mysql -u root -p$DBPASS -e "CREATE DATABASE nova_api"
sudo mysql -u root -p$DBPASS -e "CREATE DATABASE nova"
sudo mysql -u root -p$DBPASS -e "CREATE DATABASE nova_cell0"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "SHOW GRANTS FOR nova"

. admin-openrc

openstack user create --domain default --password $NOVA_PASS nova

openstack role add --project service --user nova admin

openstack service create --name nova --description "OpenStack Compute" compute

openstack endpoint create --region RegionOne compute public http://controller1:8774/v2.1

openstack endpoint create --region RegionOne compute internal http://controller1:8774/v2.1

openstack endpoint create --region RegionOne compute admin http://controller1:8774/v2.1

sudo apt install -y nova-api nova-conductor nova-novncproxy nova-scheduler

sudo cp /etc/nova/nova.conf /etc/nova/nova.conf.bak 

sudo sed -i 's/connection = sqlite:\/\/\/\/var\/lib\/nova\/nova_api.sqlite.*/connection = mysql+pymysql:\/\/nova:'"$NOVA_DBPASS"'@controller1\/nova_api/' /etc/nova/nova.conf

sudo sed -i 's/connection = sqlite:\/\/\/\/var\/lib\/nova\/nova.sqlite.*/connection = mysql+pymysql:\/\/nova:'"$NOVA_DBPASS"'@controller1\/nova/' /etc/nova/nova.conf

sudo sed -i 's/^\[api\].*/\[api\] \
auth_strategy = keystone/' /etc/nova/nova.conf

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
transport_url = rabbit:\/\/openstack:'"$RABBIT_PASS"'@controller1:5672\//' /etc/nova/nova.conf

sudo sed -i 's/^\[keystone_authtoken\].*/\[keystone_authtoken\] \
www_authenticate_uri = http:\/\/controller1:5000\/ \
auth_url = http:\/\/controller1:5000\/ \
memcached_servers = controller1:11211 \
auth_type = password \
project_domain_name = Default \
user_domain_name = Default \
project_name = service \
username = nova \
password = '"$NOVA_DBPASS"' \
  /' /etc/nova/nova.conf

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
my_ip = '"$CONTROLLER_MGMT_IPADDR"'/' /etc/nova/nova.conf

sudo sed -i 's/^\[vnc\].*/\[vnc\] \
enabled = true \
server_listen = '"$CONTROLLER_MGMT_IPADDR"' \
server_proxyclient_address = '"$CONTROLLER_MGMT_IPADDR"' \
  /' /etc/nova/nova.conf

sudo sed -i 's/^\[glance\].*/\[glance\] \
api_servers = http:\/\/controller1:9292 \
  /' /etc/nova/nova.conf

sudo sed -i 's/^\[oslo_concurrency\].*/\[oslo_concurrency\] \
lock_path = \/var\/lib\/nova\/tmp \
  /' /etc/nova/nova.conf

sudo sed -i 's/^log_dir.*/#log_dir/' /etc/nova/nova.conf

sudo sed -i 's/^\[placement\].*/\[placement\] \
region_name = RegionOne \
project_domain_name = Default \
project_name = service \
auth_type = password \
user_domain_name = Default \
auth_url = http:\/\/controller1:5000\/v3 \
username = placement \
password = '"$PLACEMENT_PASS"' \
  /' /etc/nova/nova.conf

sudo -H -u nova /bin/sh -c "nova-manage api_db sync" 

sudo -H -u nova /bin/sh -c "nova-manage cell_v2 map_cell0" 

sudo -H -u nova /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose"

sudo -H -u nova /bin/sh -c "nova-manage db sync" 

sudo -H -u nova /bin/sh -c "nova-manage cell_v2 list_cells" 

sudo service nova-api restart
sudo service nova-scheduler restart
sudo service nova-conductor restart
sudo service nova-novncproxy restart
```

Compute Node: 

```bash 
export NOVA_PASS=ved
export PLACEMENT_PASS=ved
export RABBIT_PASS=ved
export COMPUTE_MGMT_IPADDR=10.40.1.8 # management ip address of controller node

sudo apt update 
sudo apt install -y nova-compute

sudo cp /etc/nova/nova.conf /etc/nova/nova.conf.bak

sudo sed -i 's/^\[api\].*/\[api\] \
auth_strategy = keystone/' /etc/nova/nova.conf

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
transport_url = rabbit:\/\/openstack:'"$RABBIT_PASS"'@controller1/' /etc/nova/nova.conf

sudo sed -i 's/^\[keystone_authtoken\].*/\[keystone_authtoken\] \
www_authenticate_uri = http:\/\/controller1:5000\/ \
auth_url = http:\/\/controller1:5000\/ \
memcached_servers = controller1:11211 \
auth_type = password \
project_domain_name = Default \
user_domain_name = Default \
project_name = service \
username = nova \
password = '"$NOVA_PASS"' \
  /' /etc/nova/nova.conf

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
my_ip = '"$COMPUTE_MGMT_IPADDR"'/' /etc/nova/nova.conf

sudo sed -i 's/^\[vnc\].*/\[vnc\] \
enabled = true \
server_listen = 0.0.0.0 \
server_proxyclient_address = '"$COMPUTE_MGMT_IPADDR"' \
novncproxy_base_url = http:\/\/controller1:6080\/vnc_auto.html \
  /' /etc/nova/nova.conf

sudo sed -i 's/^\[glance\].*/\[glance\] \
api_servers = http:\/\/controller1:9292 \
  /' /etc/nova/nova.conf

sudo sed -i 's/^\[oslo_concurrency\].*/\[oslo_concurrency\] \
lock_path = \/var\/lib\/nova\/tmp \
  /' /etc/nova/nova.conf

sudo sed -i 's/^\[placement\].*/\[placement\] \
region_name = RegionOne \
project_domain_name = Default \
project_name = service \
auth_type = password \
user_domain_name = Default \
auth_url = http:\/\/controller1:5000\/v3 \
username = placement \
password = '"$PLACEMENT_PASS"' \
  /' /etc/nova/nova.conf

egrep -c '(vmx|svm)' /proc/cpuinfo

sudo service nova-compute restart
```

Controller: 

```bash
. admin-openrc

openstack compute service list --service nova-compute

sudo -H -u nova /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" 

openstack compute service list

openstack catalog list

openstack image list

sudo nova-status upgrade check
```

## Neutron 

OpenStack Networking (neutron) manages all networking facets for the Virtual Networking Infrastructure (VNI) and the access layer aspects of the Physical Networking Infrastructure (PNI) in your OpenStack environment. OpenStack Networking enables projects to create advanced virtual network topologies which may include services such as a firewall, and a virtual private network (VPN).

Controller: 

```bash
export DBPASS=ved
export NEUTRON_DBPASS=ved
export NEUTRON_PASS=ved
export CONTROLLER_MGMT_IPADDR=10.40.1.6 # management ip address of controller node

sudo mysql -u root -p$DBPASS -e "CREATE DATABASE neutron"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '${NEUTRON_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '${NEUTRON_DBPASS}'"

sudo mysql -u root -p$DBPASS -e "SHOW GRANTS FOR neutron"

. admin-openrc

openstack user create --domain default --password $NEUTRON_PASS neutron

openstack role add --project service --user neutron admin

openstack service create --name neutron --description "OpenStack Networking" network

openstack endpoint create --region RegionOne network public http://controller1:9696

openstack endpoint create --region RegionOne network internal http://controller1:9696

openstack endpoint create --region RegionOne network admin http://controller1:9696
```

### Self service network 

Controller: 

```bash
export NEUTRON_DBPASS=ved
export NEUTRON_PASS=ved
export RABBIT_PASS=ved
export NOVA_PASS=ved

sudo apt install -y neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent

sudo sed -i 's/connection = sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite.*/connection = mysql+pymysql:\/\/neutron:'"$NEUTRON_DBPASS"'@controller1\/neutron/' /etc/neutron/neutron.conf


# Mixed with OVN !!!!!!

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
core_plugin = ml2 \
# service_plugins = router \
allow_overlapping_ips = true \
  /' /etc/neutron/neutron.conf

# Mixed with OVN !!!!!! ^

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
transport_url = rabbit:\/\/openstack:'"$RABBIT_PASS"'@controller1/' /etc/neutron/neutron.conf 

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
auth_strategy = keystone/' /etc/neutron/neutron.conf 

sudo sed -i 's/^\[keystone_authtoken\].*/\[keystone_authtoken\] \
www_authenticate_uri = http:\/\/controller1:5000 \
auth_url = http:\/\/controller1:5000 \
memcached_servers = controller1:11211 \
auth_type = password \
project_domain_name = default \
user_domain_name = default \
project_name = service \
username = neutron \
password = '"$NEUTRON_PASS"' \
  /' /etc/neutron/neutron.conf 

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
notify_nova_on_port_status_changes = true \
notify_nova_on_port_data_changes = true \
  /' /etc/neutron/neutron.conf 

sudo sed -i 's/^\[nova\].*/\[nova\] \
auth_url = http:\/\/controller1:5000 \
auth_type = password \
project_domain_name = default \
user_domain_name = default \
region_name = RegionOne \
project_name = service \
username = nova \
password = '"$NOVA_PASS"' \
  /' /etc/neutron/neutron.conf 

sudo sed -i 's/^\[oslo_concurrency\].*/\[oslo_concurrency\] \
lock_path = \/var\/lib\/neutron\/tmp \
  /' /etc/nova/nova.conf

# Mixed with OVN !!!!!!

sudo sed -i 's/^\[ml2\].*/\[ml2\] \
type_drivers = flat,vlan,vxlan \
tenant_network_types = vxlan \
mechanism_drivers = linuxbridge,l2population \
extension_drivers = port_security \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini

# Mixed with OVN !!!!!! ^ 

sudo sed -i 's/^\[ml2_type_flat\].*/\[ml2_type_flat\] \
flat_networks = provider \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini

sudo sed -i 's/^\[ml2_type_vxlan\].*/\[ml2_type_vxlan\] \
vni_ranges = 1:1000 \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini

sudo sed -i 's/^\[securitygroup\].*/\[securitygroup\] \
enable_ipset = true \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini

```

Compute Node: 

```bash 
export NEUTRON_DBPASS=ved
export NEUTRON_PASS=ved
export RABBIT_PASS=ved
export NOVA_PASS=ved

sudo apt install -y neutron-linuxbridge-agent

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
transport_url = rabbit:\/\/openstack:'"$RABBIT_PASS"'@controller1/' /etc/neutron/neutron.conf 

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
auth_strategy = keystone/' /etc/neutron/neutron.conf 

sudo sed -i 's/^\[keystone_authtoken\].*/\[keystone_authtoken\] \
www_authenticate_uri = http:\/\/controller1:5000 \
auth_url = http:\/\/controller1:5000 \
memcached_servers = controller1:11211 \
auth_type = password \
project_domain_name = default \
user_domain_name = default \
project_name = service \
username = neutron \
password = '"$NEUTRON_PASS"' \
  /' /etc/neutron/neutron.conf 

sudo sed -i 's/^\[oslo_concurrency\].*/\[oslo_concurrency\] \
lock_path = \/var\/lib\/neutron\/tmp \
  /' /etc/nova/nova.conf
```

### Linux Bidge Agent 

The Linux bridge agent builds layer-2 (bridging and switching) virtual networking infrastructure for instances and handles security groups.

Controller: 

```bash
export PROVIDER_INTERFACE_NAME=enp5s0
export OVERLAY_INTERFACE_IP_ADDRESS=10.40.1.6

sudo sed -i 's/^\[linux_bridge\].*/\[linux_bridge\] \
physical_interface_mappings = provider:'"$PROVIDER_INTERFACE_NAME"' \
  /' /etc/neutron/plugins/ml2/linuxbridge_agent.ini

sudo sed -i 's/^\[vxlan\].*/\[vxlan\] \
enable_vxlan = true \
local_ip = '"$OVERLAY_INTERFACE_IP_ADDRESS"' \
l2_population = true \
  /' /etc/neutron/plugins/ml2/linuxbridge_agent.ini

sudo sed -i 's/^\[securitygroup\].*/\[securitygroup\] \
enable_security_group = true \
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver \
  /' /etc/neutron/plugins/ml2/linuxbridge_agent.ini

sudo echo 'net.bridge.bridge-nf-call-iptables=1' | sudo tee -a /etc/sysctl.conf

sudo echo 'net.bridge.bridge-nf-call-ip6tables=1' | sudo tee -a /etc/sysctl.conf

sudo modprobe br_netfilter

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
interface_driver = linuxbridge \
  /' /etc/neutron/l3_agent.ini

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
interface_driver = linuxbridge \
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq \
enable_isolated_metadata = true \
  /' /etc/neutron/dhcp_agent.ini
```

Compute Node: 

```bash
export PROVIDER_INTERFACE_NAME=enp5s0
export OVERLAY_INTERFACE_IP_ADDRESS=10.40.1.8

sudo sed -i 's/^\[linux_bridge\].*/\[linux_bridge\] \
physical_interface_mappings = provider:'"$PROVIDER_INTERFACE_NAME"' \
  /' /etc/neutron/plugins/ml2/linuxbridge_agent.ini

sudo sed -i 's/^\[vxlan\].*/\[vxlan\] \
enable_vxlan = true \
local_ip = '"$OVERLAY_INTERFACE_IP_ADDRESS"' \
l2_population = true \
  /' /etc/neutron/plugins/ml2/linuxbridge_agent.ini

sudo sed -i 's/^\[securitygroup\].*/\[securitygroup\] \
enable_security_group = true \
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver \
  /' /etc/neutron/plugins/ml2/linuxbridge_agent.ini

sudo echo 'net.bridge.bridge-nf-call-iptables=1' | sudo tee -a /etc/sysctl.conf

sudo echo 'net.bridge.bridge-nf-call-ip6tables=1' | sudo tee -a /etc/sysctl.conf

sudo modprobe br_netfilter

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
interface_driver = linuxbridge \
  /' /etc/neutron/l3_agent.ini

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
interface_driver = linuxbridge \
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq \
enable_isolated_metadata = true \
  /' /etc/neutron/dhcp_agent.ini
```

### Configure Compute Service to use the Networking Service 

Controller: 

```bash 
export NEUTRON_PASS=ved
export METADATA_SECRET=ved 

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
nova_metadata_host = controller1 \
metadata_proxy_shared_secret = '"$METADATA_SECRET"' \
  /' /etc/neutron/metadata_agent.ini

sudo sed -i 's/^\[neutron\].*/\[neutron\] \
auth_url = http:\/\/controller1:5000 \
auth_type = password \
project_domain_name = default \
user_domain_name = default \
region_name = RegionOne \
project_name = service \
username = neutron \
password = '"$NEUTRON_PASS"' \
service_metadata_proxy = true \
metadata_proxy_shared_secret = '"$METADATA_SECRET"' \
  /' /etc/nova/nova.conf 
```

Compute Node: 

```bash
export NEUTRON_PASS=ved

sudo sed -i 's/^\[neutron\].*/\[neutron\] \
auth_url = http:\/\/controller1:5000 \
auth_type = password \
project_domain_name = default \
user_domain_name = default \
region_name = RegionOne \
project_name = service \
username = neutron \
password = '"$NEUTRON_PASS"' \
  /' /etc/nova/nova.conf

sudo service nova-compute restart

sudo service neutron-linuxbridge-agent restart
```

### Install OVS 

Each controller node runs the OVS service (including dependent services such as ovsdb-server) and the ovn-northd service. However, only a single instance of the ovsdb-server and ovn-northd services can operate in a deployment. However, deployment tools can implement active/passive high-availability using a management tool that monitors service health and automatically starts these services on another node after failure of the primary node.

Building OVS from source automatically installs OVN for releases older than 2.13.

https://docs.ovn.org/en/latest/intro/install/general.html

Controller & Compute Node: 

```bash 
git clone https://github.com/ovn-org/ovn.git
sudo apt install -y build-essential
sudo apt install -y clang
sudo apt install -y libssl-dev
sudo apt install -y libcap-ng-utils
sudo apt install -y autoconf
sudo apt install -y automake
sudo apt install -y libtool
cd ovn
./boot.sh

git submodule update --init
cd ovs
./boot.sh
./configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc
make
sudo make install
cd ..

./configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc
make 
sudo make install
```

Controller: 

```bash
sudo /usr/share/ovn/scripts/ovn-ctl start_northd
sudo /usr/share/ovn/scripts/ovn-ctl start_controller

sudo mkdir -p /usr/local/etc/ovn
sudo ovsdb-tool create /usr/local/etc/ovn/ovnnb_db.db ovn-nb.ovsschema
sudo ovsdb-tool create /usr/local/etc/ovn/ovnsb_db.db ovn-sb.ovsschema
sudo mkdir -p /usr/local/var/run/ovn
sudo mkdir -p /usr/local/var/log/ovn

sudo /usr/share/openvswitch/scripts/ovs-ctl start  --system-id="random"

sudo ovsdb-server /usr/local/etc/ovn/ovnnb_db.db --remote=punix:/usr/local/var/run/ovn/ovnnb_db.sock \
     --remote=db:OVN_Northbound,NB_Global,connections \
     --pidfile=/usr/local/var/run/ovn/ovnnb-server.pid --detach --log-file=/usr/local/var/log/ovn/ovnnb-server.log

sudo ovsdb-server /usr/local/etc/ovn/ovnsb_db.db --remote=punix:/usr/local/var/run/ovn/ovnsb_db.sock \
     --remote=db:OVN_Southbound,SB_Global,connections \
     --pidfile=/usr/local/var/run/ovn/ovnsb-server.pid --detach --log-file=/usr/local/var/log/ovn/ovnsb-server.log

sudo ovn-nbctl --no-wait init
sudo ovn-sbctl init
sudo ovn-northd --pidfile --detach --log-file
```

Compute Node: 

```bash 
export CONTROLLER_MGMT_IPADDR=10.40.1.6 # management ip address of controller node
export OVERLAY_INTERFACE_IP_ADDRESS=10.40.1.8

sudo /usr/share/openvswitch/scripts/ovs-ctl start  --system-id="random"
sudo ovs-vsctl set open . external-ids:ovn-remote=tcp:$CONTROLLER_MGMT_IPADDR:6642
sudo ovs-vsctl set open . external-ids:ovn-encap-type=geneve,vxlan
sudo ovs-vsctl set open . external-ids:ovn-encap-ip=$OVERLAY_INTERFACE_IP_ADDRESS
sudo /usr/share/ovn/scripts/ovn-ctl start_controller

sudo ovsdb-tool create /usr/local/etc/ovn/ovnnb_db.db ovn-nb.ovsschema
sudo ovsdb-tool create /usr/local/etc/ovn/ovnsb_db.db ovn-sb.ovsschema
sudo mkdir -p /usr/local/var/run/ovn
sudo mkdir -p /usr/local/var/log/ovn

sudo ovsdb-server /usr/local/etc/ovn/ovnnb_db.db --remote=punix:/usr/local/var/run/ovn/ovnnb_db.sock \
     --remote=db:OVN_Northbound,NB_Global,connections \
     --pidfile=/usr/local/var/run/ovn/ovnnb-server.pid --detach --log-file=/usr/local/var/log/ovn/ovnnb-server.log

sudo ovsdb-server /usr/local/etc/ovn/ovnsb_db.db --remote=punix:/usr/local/var/run/ovn/ovnsb_db.sock \
     --remote=db:OVN_Southbound,SB_Global,connections \
     --pidfile=/usr/local/var/run/ovn/ovnsb-server.pid --detach --log-file=/usr/local/var/log/ovn/ovnsb-server.log

sudo /usr/share/ovn/scripts/ovn-ctl start_northd

sudo ovn-nbctl --no-wait init
sudo ovn-sbctl init
# sudo ovn-northd --pidfile --detach --log-file
```

Controller Node: 

```bash 
export OVN_L3_SCHEDULER=leastloaded
export CONTROLLER_MGMT_IPADDR=10.40.1.6 # management ip address of controller node

sudo /usr/share/openvswitch/scripts/ovs-ctl start  --system-id="random"

sudo ovn-nbctl set-connection ptcp:6641:$CONTROLLER_MGMT_IPADDR -- set connection . inactivity_probe=60000

sudo ovn-sbctl set-connection ptcp:6642:$CONTROLLER_MGMT_IPADDR -- set connection . inactivity_probe=60000

sudo /usr/share/ovn/scripts/ovn-ctl start_northd

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
core_plugin = ml2 \
service_plugins = ovn-router \
  /' /etc/neutron/neutron.conf

sudo sed -i 's/^\[ml2\].*/\[ml2\] \
mechanism_drivers = ovn \
type_drivers = local,flat,vlan,geneve \
tenant_network_types = geneve,vlan \
extension_drivers = port_security \
overlay_ip_version = 4 \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini

sudo sed -i 's/^\[ml2_type_geneve\].*/\[ml2_type_geneve\] \
vni_ranges = 1:65536 \
max_header_size = 38 \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini

sudo sed -i 's/^\[securitygroup\].*/\[securitygroup\] \
enable_security_group = true \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini


# Add mannually, missing header
sed -i -e '$a[ovn\] \
ovn_nb_connection = tcp:'"$CONTROLLER_MGMT_IPADDR"':6641 \
ovn_sb_connection = tcp:'"$CONTROLLER_MGMT_IPADDR"':6642 \
ovn_l3_scheduler = '"$OVN_L3_SCHEDULER"' \
  ' /etc/neutron/plugins/ml2/ml2_conf.ini

sudo ovs-vsctl set open . external-ids:ovn-cms-options=enable-chassis-as-gw
sudo systemctl restart neutron-server
```

# Configure the metadata agent 

Controller: 

```bash
export METADATA_SECRET=ved 

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
nova_metadata_host = controller1 \
metadata_proxy_shared_secret = '"$METADATA_SECRET"' \
  /' /etc/neutron/metadata_agent.ini
```

# Configure Compute service to use the Networking service 

Controller: 

```bash
export METADATA_SECRET=ved 
export NEUTRON_PASS=ved

sudo sed -i 's/^\[neutron\].*/\[neutron\] \
auth_url = http:\/\/controller1:5000 \
auth_type = password \
project_domain_name = default \
user_domain_name = default \
region_name = RegionOne \
project_name = service \
username = neutron \
password = '"$NEUTRON_PASS"' \
service_metadata_proxy = true \
metadata_proxy_shared_secret = '"$METADATA_SECRET"' \
  /' /etc/nova/nova.conf

sudo -H -u neutron /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" 

sudo service nova-api restart

sudo service neutron-server restart
sudo service neutron-linuxbridge-agent restart
sudo service neutron-dhcp-agent restart
sudo service neutron-metadata-agent restart
sudo service neutron-l3-agent restart

```

## Horizon 

cat /var/log/apache2/error.log

OPENSTACK_KEYSTONE_URL = "http://%s:5000/identity/v3" % OPENSTACK_HOST

## Cinder 

## Swift 

## Heat 

## Reset 

sudo mysql -u root -p$DBPASS -e "DROP database keystone"

sudo mysql -u root -p$DBPASS -e "REVOKE ALL PRIVILEGES, GRANT OPTION FROM keystone"

sudo mysql -u root -p$DBPASS -e "DROP USER keystone";

sudo apt remove -y keystone; sudo apt -y autoremove

sudo rm -r /var/lib/keystone

sudo rm -r /etc/keystone/

sudo rm /etc/apache2/sites-available/keystone.conf 

sudo systemctl stop apache2 

#
