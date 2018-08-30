#systemctl stop NetworkManager
#systemctl disable NetworkManager
#scp root@deploy:/root/workspace/ifcfg-enp2s0f0:0 /etc/sysconfig/network-scripts/

cat > /etc/sysconfig/network-scripts/ifcfg-enp2s0f0.3 << EOF
DEVICE="enp2s0f0.3"
ONBOOT="yes"
BOOTPROTO="none"
PREFIX="24"
NETWORK="192.168.3.0"
VLAN="yes"
EOF

IP=$(cat /etc/sysconfig/network-scripts/ifcfg-enp2s0f0 | grep IPADDR | cut -c 19-20)

echo IPADDR=\"192.168.3.$IP\" >> /etc/sysconfig/network-scripts/ifcfg-enp2s0f0.3

#ifup ifcfg-enp2s0f0.3






