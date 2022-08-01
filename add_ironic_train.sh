#!/bin/bash

operation_node=111

case $operation_node in
    106)
        asset_num="dell"
        ipmi_ipaddr="xxx.xxx.xxx.xxx"
        ipmi_terminal_port=10111
        ipmi_user="root"
        ipmi_pass="xxxxxxx"
        cpu_sum=24
        mem_size=$[16*1024] #MB
        os_disk_size=300 #GB
        flavor_name="ecs.cbm1"
        flavor_property_resources="CUSTOM_BAREMETAL_CBM1=1"
        flavor_resource_class="baremetal.cbm1"
        switch_mt_port_mac="b0:f9:xx:xx:xx:49"
        switch_info="SA6800-1"
        port1_switch_id="Ten-GigabitEthernet1/0/15"
        port1_server_mac="3c:fd:xx:xx:xx:82"
        port2_switch_id="Ten-GigabitEthernet2/0/15"
        port2_server_mac="3c:fd:xx:xx:xx:80"
        ;;
    169)
        asset_num="dell"
        ipmi_ipaddr="xxx.xxx.xxx.xxx"
        ipmi_terminal_port=10169
        ipmi_user="root"
        ipmi_pass="xxxxxxxx"
        cpu_sum=40
        mem_size=$[504*1024] #MB
        os_disk_size=300 #GB
        flavor_name="ecs.cbm2"
        flavor_property_resources="CUSTOM_BAREMETAL_CBM2=1"
        flavor_resource_class="baremetal.cbm2"
        switch_mt_port_mac="90:e7:xx:xx:xx:b6"
        switch_info="S6800-2.1/2-PGW"
        port1_switch_id="Ten-GigabitEthernet1/0/18"
        port1_server_mac="a0:36:xx:xx:xx:54"
        port2_switch_id="Ten-GigabitEthernet2/0/19"
        port2_server_mac="a0:36:xx:xx:xx:56"
        ;;
    *)
        echo "Hello boy, what are you doing ?"
        exit 1
esac

export OS_BAREMETAL_API_VERSION=1.46

node_ip_flag=$(echo "$ipmi_ipaddr" | awk -F '.' '{print $3}')-$(echo "$ipmi_ipaddr" | awk -F '.' '{print $4}')
node_name="${asset_num}_${node_ip_flag}"
echo "node name $node_name"

echo "IPMI network testing ......"
ipmitool -I lanplus -H $ipmi_ipaddr -U $ipmi_user -P $ipmi_pass chassis power status
if test $? -ne 0; then
    echo "[ERROR] IPMI network test failed, please check it"
    exit 1
fi

echo "Searching node list ......"
openstack baremetal node list -f value -c Name | grep "$node_name" >& /dev/null
if test $? -ne 0; then
    echo "Creating node ......."
    openstack baremetal node create --driver ipmi --name $node_name
    if test $? -ne 0; then
        echo "[ERROR] command failed, check it !!!"
        exit
    fi
fi
echo "Getting node uuid ......"
node_uuid=$(openstack baremetal node show $node_name -f value -c uuid)
echo "node uuid: $node_uuid"

echo "Getting vmlinuz_img_id and initrd_img_id ......"
vmlinuz_img_id=$(openstack image show ironic-agent.kernel -f value -c id)
initrd_img_id=$(openstack image show ironic-agent.initramfs -f value -c id)
echo "vmlinuz_img_id: $vmlinuz_img_id"
echo "initrd_img_id: $initrd_img_id"

echo "Node setting driver info ......"
openstack baremetal node set \
  --driver-info ipmi_username=$ipmi_user \
  --driver-info ipmi_password=$ipmi_pass \
  --driver-info ipmi_address=$ipmi_ipaddr \
  --driver-info deploy_kernel=$vmlinuz_img_id \
  --driver-info deploy_ramdisk=$initrd_img_id \
  --driver-info ipmi_terminal_port=$ipmi_terminal_port \
  $node_uuid
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Node setting deploy interface ......"
openstack baremetal node set --deploy-interface iscsi $node_uuid
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Node setting property ......"
openstack baremetal node set \
  --property capabilities="boot_option:local" \
  --property cpus=$cpu_sum \
  --property memory_mb=$mem_size  \
  --property local_gb=$os_disk_size \
  --property cpu_arch=x86_64 \
  $node_uuid
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Searching port group list ......"
port_group_name="${node_name}_PortGroup_0"
openstack baremetal port group list -f value -c Name | grep "$port_group_name" >& /dev/null
if test $? -ne 0; then
    echo "Creating port group ......"
    openstack baremetal port group create --node $node_uuid --name $port_group_name --mode active-backup --property miimon=100 --address $port1_server_mac
    if test $? -ne 0; then
        echo "[ERROR] command failed, check it !!!"
        exit
    fi
fi

echo "Getting port group uuid ......"
port_group_uuid=$(openstack baremetal port group show $port_group_name -f value -c uuid)
echo "port_group_uuid: $port_group_uuid"

echo "Port1 creating ......"
openstack baremetal port create \
  --node $node_uuid \
  --port-group $port_group_uuid \
  --local-link-connection port_id=$port1_switch_id \
  --local-link-connection switch_id=$switch_mt_port_mac \
  --local-link-connection switch_info=$switch_info \
  --pxe-enabled true $port1_server_mac
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Port2 creating ......"
openstack baremetal port create \
  --node $node_uuid \
  --port-group $port_group_uuid \
  --local-link-connection port_id=$port2_switch_id \
  --local-link-connection switch_id=$switch_mt_port_mac \
  --local-link-connection switch_info=$switch_info \
  --pxe-enabled false $port2_server_mac
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Getting my images id ......"
my_img_id=$(openstack image show my-image -f value -c id)
my_kernel_img_id=$(openstack image show ironic-agent.kernel -f value -c id)
my_initrd_img_id=$(openstack image show ironic-agent.initramfs -f value -c id)
echo "my_img_id: $my_img_id"
echo "my_kernel_img_id: $my_kernel_img_id"
echo "my_initrd_img_id: $my_initrd_img_id"

echo "Node setting instance info ......"
openstack baremetal node set \
  --instance-info image_source=$my_img_id \
  --instance-info kernel=$my_kernel_img_id \
  --instance-info ramdisk=$my_initrd_img_id \
  --instance-info root_gb=$os_disk_size \
  $node_uuid
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Node validate ......"
openstack baremetal node validate $node_uuid
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Getting rescue images id ......"
rescue_initrd_img_id=$(openstack image show rescue-ubuntu.initramfs -f value -c id)
rescue_kernel_img_id=$(openstack image show rescue-ubuntu.kernel -f value -c id)
echo "rescue_initrd_img_id: $rescue_initrd_img_id"
echo "rescue_kernel_img_id: $rescue_kernel_img_id"

echo "Node setting driver info (rescue) ......"
openstack baremetal node set \
  --driver-info rescue_ramdisk=$rescue_initrd_img_id \
  --driver-info rescue_kernel=$rescue_kernel_img_id \
  $node_uuid

echo "Node validate ......"
openstack baremetal node validate $node_uuid
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Node manage ......"
openstack baremetal node manage $node_uuid
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Node provide ......"
openstack baremetal node provide $node_uuid
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Node setting rescue interface ......"
openstack baremetal node set $node_uuid --rescue-interface agent
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Node validate ......"
openstack baremetal node validate $node_uuid
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Node setting console interface ......"
openstack baremetal node set $node_uuid --console-interface ipmitool-socat
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Node console enable ......"
openstack baremetal node console enable $node_uuid
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Searching flavor list ......"
openstack flavor list -f value -c Name | grep "$flavor_name" >& /dev/null
if test $? -ne 0; then
    echo "Creating flavor ......"
    openstack flavor create --ram $mem_size --vcpus $cpu_sum --disk $os_disk_size --id $flavor_name  $flavor_name
    if test $? -ne 0; then
        echo "[ERROR] command failed, check it !!!"
        exit
    fi
    echo "Flavor set resources ......"
    openstack flavor set --property resources:$flavor_property_resources $flavor_name
    if test $? -ne 0; then
        echo "[ERROR] command failed, check it !!!"
        exit
    fi
fi

echo "Node setting resource class ......"
openstack baremetal node set $node_uuid --resource-class $flavor_resource_class
if test $? -ne 0; then
    echo "[ERROR] command failed, check it !!!"
    exit
fi

echo "Create finished, OK"
