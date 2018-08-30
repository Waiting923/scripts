#!/bin/bash
ceph=$(mount | grep ceph | awk '{ print $1 }')
ceph_mount=$(mount | grep ceph | awk ' { print $3 }')


for a in $ceph_mount
do
    echo ${a:0:-1}
    echo "---------umount " $a " ---------"
    umount $a
    sleep 1
done

for dev in $ceph
do
    echo ${dev:0:-1}
    echo "---------now clean disk partition " ${dev:0:-1} " -----------"
    sgdisk --zap-all --clear --mbrtogpt ${dev:0:-1}
done
