## Setup Openstack Controller

####################################################################################
# Set time-date on server 
####################################################################################

sudo sudo timedatectl set-timezone Europe/London
sudo timedatectl set-ntp on

####################################################################################
# Set environment variables
####################################################################################

# Management ip address of the controller node
export CONTROLLER_MGMT_IPADDR=10.40.1.6
# Management ip address of the compute node 
export COMPUTE1_MGMT_IPADDR=10.40.1.8 
# Management subnet
export MGMT_SUBNET=10.40.1.0/24
# MySQL root password
export MYSQL_ROOT_PASSWORD=ved
# RabbitMQ password 
export RABBIT_PASS=ved
# Keystone mysql database password 
export KEYSTONE_DBPASS=ved
# Keystone Openstack admin password 
export KEYSTONE_ADMIN_PASS=ved

# Openstack admin username
export OS_USERNAME=admin
# Openstack admin password 
export OS_PASSWORD=$KEYSTONE_ADMIN_PASS
# Openstack admin project name
export OS_PROJECT_NAME=admin
# Openstack default user domain
export OS_USER_DOMAIN_NAME=Default
# Openstack default project domain
export OS_PROJECT_DOMAIN_NAME=Default
# Openstack Keystone authentication url
export OS_AUTH_URL=http://controller1:5000/v3
# Openstack Identity API Version
export OS_IDENTITY_API_VERSION=3

# Glance MySQL user password 
export GLANCE_DBPASS=ved
# Openstack Glance password
export GLANCE_PASS=ved

# Placement MySQL user password 
export PLACEMENT_DBPASS=ved
# Openstack Placement password
export PLACEMENT_PASS=ved

# Nova MySQL user password 
export NOVA_DBPASS=ved
# Openstack Nova password
export NOVA_PASS=ved

# Neutron MySQL user password 
export NEUTRON_DBPASS=ved
# Openstack Neutron password
export NEUTRON_PASS=ved

# Provider network interface name
export PROVIDER_INTERFACE_NAME=enp5s0
# Overlay network interface address (same as management in this install)
export OVERLAY_INTERFACE_IP_ADDRESS=10.40.1.6
# Neutron metadata proxy secret
export METADATA_SECRET=ved 

# Cinder MySQL user password
export CINDER_DBPASS=ved 
# Openstack Cinder password
export CINDER_PASS=ved

####################################################################################
## DNS Hosts 
####################################################################################

# Controller node 
sudo sed -i '/^127.0.0.1 localhost.*/a '"$CONTROLLER_MGMT_IPADDR"' controller1' /etc/hosts
# Compute node 
sudo sed -i '/^127.0.0.1 localhost.*/a '"$COMPUTE1_MGMT_IPADDR"' compute1' /etc/hosts

####################################################################################
## Network Time Protocl (NTP) 
####################################################################################

# To properly synchronize services among nodes using Chrony, an implementation of 
# NTP. Configure the controller node to reference more accurate (lower stratum) 
# servers and other nodes to reference the controller node

sudo apt install -y chrony
# Possible to reference more accurate NTP servers with line 'server NTP_SERVER iburst'
sudo sed -i -e '$a #Permit Node Connections\nallow '"$MGMT_SUBNET"'' /etc/chrony/chrony.conf
sudo service chrony restart

# Verify:
# chronyc sources

####################################################################################
## Ubuntu OpenStack packages 
####################################################################################

# https://docs.openstack.org/install-guide/environment-packages-ubuntu.html#finalize-the-installation

sudo add-apt-repository -y cloud-archive:wallaby
sudo apt dist-upgrade -y 
sudo apt update

####################################################################################
## OpenStack Client 
####################################################################################

sudo apt install -y python3-openstackclient

####################################################################################
## SQL Database 
####################################################################################

# Most OpenStack services use an SQL database to store information. The database 
# typically runs on the controller node.

# https://docs.openstack.org/install-guide/environment-sql-database-ubuntu.html

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

####################################################################################
# Message Queue 
####################################################################################

# Message queue to coordinate operations and status information among services. 
# The message queue service typically runs on the controller node

# https://docs.openstack.org/install-guide/environment-messaging-ubuntu.html

sudo apt install -y rabbitmq-server
sudo rabbitmqctl add_user openstack $RABBIT_PASS
sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*"

####################################################################################
# Memcached (Token Caching) 
####################################################################################

# The Identity service authentication mechanism for services uses Memcached to cache 
# tokens. The memcached service typically runs on the controller node. 

# !!! For production deployments, we recommend enabling a combination of 
# firewalling, authentication, and encryption to secure it.

# https://docs.openstack.org/install-guide/environment-memcached-ubuntu.html

sudo apt install -y memcached libmemcached-tools
sudo sed -i 's/-l 127.0.0.1.*/-l '"$CONTROLLER_MGMT_IPADDR"'/' /etc/memcached.conf
sudo service memcached restart

####################################################################################
# ETCD 
####################################################################################

# OpenStack services may use Etcd, a distributed reliable key-value store for 
# distributed key locking, storing configuration, keeping track of service live-ness 
# and other scenarios.

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

####################################################################################
# Keystone 
####################################################################################

# The OpenStack Identity service provides a single point of integration for managing 
# authentication, authorization, and a catalog of services.

# !!! For simplicity, this guide uses the management network for all endpoint types 
# and the default RegionOne region

# https://docs.openstack.org/keystone/latest/install/index-ubuntu.html

sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE keystone"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '${KEYSTONE_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW GRANTS FOR keystone"

sudo apt install -y keystone

sudo cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.bak 

# To reinstall if config files previously purged 
# sudo apt install --reinstall -o Dpkg::Options::="--force-confask,confnew,confmiss" keystone
# sudo apt install --reinstall -o Dpkg::Options::="--force-confask,confnew,confmiss" $(dpkg -S /etc/keystone | sed 's/,//g; s/:.*//')

sudo sed -i 's/connection = sqlite:\/\/\/\/var\/lib\/keystone\/keystone.db.*/connection = mysql+pymysql:\/\/keystone:'"$KEYSTONE_DBPASS"'@controller1\/keystone/' /etc/keystone/keystone.conf

sudo sed -i 's/#provider = fernet.*/provider = fernet/' /etc/keystone/keystone.conf

sudo -H -u keystone /bin/sh -c "keystone-manage db_sync" 

sudo keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

sudo keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

sudo keystone-manage bootstrap --bootstrap-password "$KEYSTONE_ADMIN_PASS" \
  --bootstrap-admin-url http://controller1:5000/v3/ \
  --bootstrap-internal-url http://controller1:5000/v3/ \
  --bootstrap-public-url http://controller1:5000/v3/ \
  --bootstrap-region-id RegionOne

sudo sed -i -e '$aServerName controller1' /etc/apache2/apache2.conf

sudo service apache2 restart

openstack domain create --description "Domain 1" domain1
openstack project create --domain default --description "Service Project" service
openstack --os-auth-url http://controller1:5000/v3   --os-project-domain-name Default --os-user-domain-name Default   --os-project-name admin --os-username admin token issue

echo "
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$KEYSTONE_ADMIN_PASS
export OS_AUTH_URL=http://controller1:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
" | sudo tee -a ~/admin-openrc > /dev/null 

. admin-openrc
openstack token issue

####################################################################################
## Glance 
####################################################################################

# Image service (glance) enables users to discover, register, and retrieve virtual 
# machine images. It offers a REST API that enables you to query virtual machine 
# image metadata and retrieve an actual image. You can store virtual machine images 
# made available through the Image service in a variety of locations, from simple 
# file systems to object-storage systems like OpenStack Object Storage.

# !!! For simplicity, this guide describes configuring the Image service to use the 
# file back end, which uploads and stores in a directory on the controller node 
# hosting the Image service. By default, this directory is /var/lib/glance/images/.

# https://docs.openstack.org/glance/wallaby/install/install-ubuntu.html


sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE glance"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '${GLANCE_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '${GLANCE_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW GRANTS FOR glance"

. admin-openrc

openstack user create --domain default --password $GLANCE_PASS glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://controller1:9292
openstack endpoint create --region RegionOne image internal http://controller1:9292
openstack endpoint create --region RegionOne image admin http://controller1:9292

sudo apt install -y glance

sudo cp /etc/glance/glance-api.conf /etc/glance/glance-api.conf.bak 

# To reinstall if config files previously purged 
# sudo apt install --reinstall -o Dpkg::Options::="--force-confask,confnew,confmiss" glance
# sudo apt install --reinstall -o Dpkg::Options::="--force-confask,confnew,confmiss" $(dpkg -S /etc/glance | sed 's/,//g; s/:.*//')

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

####################################################################################
## Placement 
####################################################################################

# Placement provides a placement-api WSGI script for running the service with 
# Apache, nginx or other WSGI-capable web servers. Depending on what packaging 
# solution is used to deploy OpenStack, the WSGI script may be in /usr/bin or 
# /usr/local/bin.

# !!! use an endpoint URL of http://controller1:8778/ as an example only. 
# You should configure placement to use whatever hostname and port works best for 
# your environment. Using SSL on the default port, with either a domain or path 
# specific to placement, is recommended. For example: 
# https://mygreatcloud.com/placement or https://placement.mygreatcloud.com/.

# https://docs.openstack.org/placement/wallaby/install/install-ubuntu.html

sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE placement"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '${PLACEMENT_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '${PLACEMENT_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW GRANTS FOR placement"

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

####################################################################################
# Nova - Controller Node 
####################################################################################

# OpenStack Compute interacts with OpenStack Identity for authentication, OpenStack 
# Placement for resource inventory tracking and selection, OpenStack Image service 
# for disk and server images, and OpenStack Dashboard for the user and 
# administrative interface. Image access is limited by projects, and by users; 
# quotas are limited per project (the number of instances, for example). OpenStack 
# Compute can scale horizontally on standard hardware, and download images to 
# launch instances.

sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE nova_api"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE nova"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE nova_cell0"

sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '${NOVA_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW GRANTS FOR nova"

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

# Verify: 

# . admin-openrc
# openstack compute service list --service nova-compute
# sudo -H -u nova /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" 
# openstack compute service list
# openstack catalog list
# openstack image list
# sudo nova-status upgrade check

####################################################################################
# Neutron 
####################################################################################

# OpenStack Networking (neutron) manages all networking facets for the Virtual 
# Networking Infrastructure (VNI) and the access layer aspects of the Physical 
# Networking Infrastructure (PNI) in your OpenStack environment. OpenStack 
# Networking enables projects to create advanced virtual network topologies which 
# may include services such as a firewall, and a virtual private network (VPN).

sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE neutron"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '${NEUTRON_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '${NEUTRON_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW GRANTS FOR neutron"

. admin-openrc

openstack user create --domain default --password $NEUTRON_PASS neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://controller1:9696
openstack endpoint create --region RegionOne network internal http://controller1:9696
openstack endpoint create --region RegionOne network admin http://controller1:9696

# Self service network
# Configure the server component

sudo apt install -y neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent

sudo sed -i 's/connection = sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite.*/connection = mysql+pymysql:\/\/neutron:'"$NEUTRON_DBPASS"'@controller1\/neutron/' /etc/neutron/neutron.conf

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
core_plugin = ml2 \
# service_plugins = router \
allow_overlapping_ips = true \
  /' /etc/neutron/neutron.conf

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

sudo sed -i 's/^\[ml2\].*/\[ml2\] \
type_drivers = flat,vlan,vxlan \
tenant_network_types = vxlan \
mechanism_drivers = linuxbridge,l2population \
extension_drivers = port_security \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini

sudo sed -i 's/^\[ml2_type_flat\].*/\[ml2_type_flat\] \
flat_networks = provider \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini

sudo sed -i 's/^\[ml2_type_vxlan\].*/\[ml2_type_vxlan\] \
vni_ranges = 1:1000 \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini

sudo sed -i 's/^\[securitygroup\].*/\[securitygroup\] \
enable_ipset = true \
  /' /etc/neutron/plugins/ml2/ml2_conf.ini

# Linux Bidge Agent 

# The Linux bridge agent builds layer-2 (bridging and switching) virtual networking 
# infrastructure for instances and handles security groups.

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

# Configure L3 agent

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
interface_driver = linuxbridge \
  /' /etc/neutron/l3_agent.ini

# Configure DHCP agent

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
interface_driver = linuxbridge \
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq \
enable_isolated_metadata = true \
  /' /etc/neutron/dhcp_agent.ini

# Configure the metadata agent

export METADATA_SECRET=ved 

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
nova_metadata_host = controller1 \
metadata_proxy_shared_secret = '"$METADATA_SECRET"' \
  /' /etc/neutron/metadata_agent.ini

# Configure Compute service to use the Networking service 

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

# Restart services 

sudo service nova-api restart
sudo service neutron-server restart
sudo service neutron-linuxbridge-agent restart
sudo service neutron-dhcp-agent restart
sudo service neutron-metadata-agent restart
sudo service neutron-l3-agent restart

####################################################################################
# Horizon 
####################################################################################

# sudo apt install -y openstack-dashboard

# sudo cp /etc/openstack-dashboard/local_settings.py /etc/openstack-dashboard/local_settings.py.bak

# sudo sed -i 's/^OPENSTACK_HOST =.*/OPENSTACK_HOST = "10.40.1.6"/' /etc/openstack-dashboard/local_settings.py

# sudo sed -i 's/^#SESSION_ENGINE =.*/SESSION_ENGINE = "django.contrib.sessions.backends.cache"/' /etc/openstack-dashboard/local_settings.py

# sudo sed -e '/CACHES =.*/,+5 s/^/#/' /etc/openstack-dashboard/local_settings.py

# sed -i -e '$aTEXTTOEND' filename

# /etc/openstack-dashboard/local_settings.py


# cat /var/log/apache2/error.log

# OPENSTACK_KEYSTONE_URL = "http://%s:5000/identity/v3" % OPENSTACK_HOST

####################################################################################
# Cinder 
####################################################################################

# Configure controller 

sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE cinder"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '${CINDER_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '${CINDER_DBPASS}'"
sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SHOW GRANTS FOR cinder"

. admin-openrc

openstack user create --domain default --password $CINDER_PASS cinder
openstack role add --project service --user cinder admin
openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
openstack endpoint create --region RegionOne volumev2 public http://controller1:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev2 internal http://controller1:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev2 admin http://controller1:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 public http://controller1:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 internal http://controller1:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 admin http://controller1:8776/v3/%\(project_id\)s

sudo apt install -y cinder-api cinder-scheduler

sudo sed -i 's/connection = sqlite:\/\/\/\/var\/lib\/cinder\/cinder.sqlite.*/connection = mysql+pymysql:\/\/cinder:'"$CINDER_DBPASS"'@controller1\/cinder/' /etc/cinder/cinder.conf

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
transport_url = rabbit:\/\/openstack:'"$RABBIT_PASS"'@controller1 \
auth_strategy = keystone \
my_ip = '"$CONTROLLER_MGMT_IPADDR"' \
  /' /etc/cinder/cinder.conf 

sudo sed -i -e '$a\[keystone_authtoken\] \
www_authenticate_uri = http:\/\/controller1:5000 \
auth_url = http:\/\/controller1:5000 \
memcached_servers = controller1:11211 \
auth_type = password \
project_domain_name = default \
user_domain_name = default \
project_name = service \
username = cinder \
password = '"$CINDER_PASS"'' /etc/cinder/cinder.conf 

sudo sed -i -e '$a\[oslo_concurrency\] \
lock_path = /var/lib/cinder/tmp' /etc/cinder/cinder.conf 

sudo -H -u cinder /bin/sh -c "cinder-manage db sync" 

sudo sed -i 's/^\[cinder\].*/\[cinder\] \
os_region_name = RegionOne \
  /' /etc/nova/nova.conf

sudo service nova-api restart
sudo service cinder-scheduler restart
sudo service apache2 restart

####################################################################################
# Swift 
####################################################################################

####################################################################################
# Heat 
####################################################################################

####################################################################################
# Reset 
####################################################################################

# sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DROP database keystone"

# sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "REVOKE ALL PRIVILEGES, GRANT OPTION FROM keystone"

# sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DROP USER keystone";

# sudo apt remove -y keystone; sudo apt -y autoremove

# sudo rm -r /var/lib/keystone

# sudo rm -r /etc/keystone/

# sudo rm /etc/apache2/sites-available/keystone.conf 

# sudo systemctl stop apache2 

