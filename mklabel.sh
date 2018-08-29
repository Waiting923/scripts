HOSTNAME=$(hostname | cut -c1-7)
if [ $HOSTNAME != storage ]
then
	for i in {b..g}
		do parted /dev/sd$i -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_BOOTSTRAP 1 -1
	done
else
	for i in {b..g}
		do parted /dev/sd$i -s -- mklabel gpt mkpart KOLLA_CEPH_OSD_CACHE_BOOTSTRAP 1 -1
	done
fi
#use to mklabel on disks or partes
