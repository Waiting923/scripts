#sed -i -e 's/BOOTPROTO=dhcp/BOOTPROTO=static' -e 's/ONBOOT=no/ONBOOT=yes' /etc/sysconfig/network-scripts/ifcfg-$1
#用法 sh 脚本 网卡名 配置的网段
IP=$(cat /etc/sysconfig/network-scripts/ifcfg-enp2s0f0 | grep IPADDR | cut -c 19-20)
sed -i -e 's/BOOTPROTO=none/BOOTPROTO=static/' -e 's/ONBOOT=no/ONBOOT=yes/' -e "1i\IPADDR=192.168."$2"."$IP"" -e '2i\NETMASK=255.255.255.0'     ./ifcfg-$1
