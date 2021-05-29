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

# RabbitMQ password 
export RABBIT_PASS=ved
# Openstack Placement password
export PLACEMENT_PASS=ved
# Openstack Nova password
export NOVA_PASS=ved
# Openstack Neutron password
export NEUTRON_PASS=ved

# Provider network interface name
export PROVIDER_INTERFACE_NAME=enp5s0
# Overlay network interface address (same as management in this install)
export OVERLAY_INTERFACE_IP_ADDRESS=10.40.1.8

# Volume device device for vm block storage 
export OBJECT_STORAGE_VOLUME=/dev/sda

# Openstack Cinder password
export CINDER_PASS=ved
# Cinder MySQL database password 
export CINDER_DBPASS=ved
# RabbitMQ password 
export RABBIT_PASS=ved

####################################################################################
# DNS Hosts 
####################################################################################

# Controller node 
sudo sed -i '/^127.0.0.1 localhost.*/a '"$CONTROLLER_MGMT_IPADDR"' controller1' /etc/hosts
# Compute node 
sudo sed -i '/^127.0.0.1 localhost.*/a '"$COMPUTE1_MGMT_IPADDR"' compute1' /etc/hosts

####################################################################################
# Network Time Protocl (NTP) 
####################################################################################

# To properly synchronize services among nodes using Chrony, an implementation of 
# NTP. Configure the controller node to reference more accurate (lower stratum) 
# servers and other nodes to reference the controller node

sudo apt install -y chrony
sudo sed -i -e '$a #Source Server\nserver controller1 iburst' /etc/chrony/chrony.conf
sudo sed -e '/pool.*/s/^/#/g' -i /etc/chrony/chrony.conf
sudo service chrony restart

# Verify:
# chronyc sources

####################################################################################
# Ubuntu OpenStack packages 
####################################################################################

# https://docs.openstack.org/install-guide/environment-packages-ubuntu.html#finalize-the-installation

sudo add-apt-repository -y cloud-archive:wallaby
sudo apt dist-upgrade -y 
sudo apt update

####################################################################################
# OpenStack Client 
####################################################################################

sudo apt install -y python3-openstackclient

####################################################################################
# Nova - Controller Node 
####################################################################################

# OpenStack Compute interacts with OpenStack Identity for authentication, OpenStack 
# Placement for resource inventory tracking and selection, OpenStack Image service 
# for disk and server images, and OpenStack Dashboard for the user and 
# administrative interface. Image access is limited by projects, and by users; 
# quotas are limited per project (the number of instances, for example). OpenStack 
# Compute can scale horizontally on standard hardware, and download images to launch 
# instances.

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
my_ip = '"$COMPUTE1_MGMT_IPADDR"'/' /etc/nova/nova.conf

sudo sed -i 's/^\[vnc\].*/\[vnc\] \
enabled = true \
server_listen = 0.0.0.0 \
server_proxyclient_address = '"$COMPUTE1_MGMT_IPADDR"' \
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

# Self-service network
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

# Configure Compute Service to use the Networking Service 

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

####################################################################################
# Cinder 
####################################################################################

# Before you install and configure the Block Storage service on the storage node, 
# you must prepare the storage device.

# Check partitions with '$ cat /proc/partitions'
sudo apt install -y lvm2 thin-provisioning-tools

sudo vgcreate cinder-volumes $OBJECT_STORAGE_VOLUME

# Check if existing partitions are using LVM (if so add to filter with 'a' accept):
# sudo lvm pvdisplay

sudo sed -i 's/^devices {.*/devices { \
        filter = \[ "a\/sda\/", "r\/\.\*\/"] \
  /' /etc/lvm/lvm.conf 

# Install and configure components 

sudo apt install -y cinder-volume

sudo sed -i 's/connection = sqlite:\/\/\/\/var\/lib\/cinder\/cinder.sqlite.*/connection = mysql+pymysql:\/\/cinder:'"$CINDER_DBPASS"'@controller1\/cinder/' /etc/cinder/cinder.conf

sudo sed -i 's/^\[DEFAULT\].*/\[DEFAULT\] \
transport_url = rabbit:\/\/openstack:'"$RABBIT_PASS"'@controller1 \
auth_strategy = keystone \
my_ip = '"$COMPUTE1_MGMT_IPADDR"' \
enabled_backends = lvm \
glance_api_servers = http:\/\/controller1:9292 \
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

sudo sed -i -e '$a\[lvm\] \
volume_driver = cinder\.volume\.drivers\.lvm\.LVMVolumeDriver \
volume_group = cinder-volumes \
target_protocol = iscsi \
target_helper = tgtadm' /etc/cinder/cinder.conf 

sudo sed -i -e '$a\[oslo_concurrency\] \
lock_path = /var/lib/cinder/tmp' /etc/cinder/cinder.conf 

sudo service cinder-volume restart

# Verify: 

sudo cinder-status upgrade check