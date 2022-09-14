#!/bin/bash
#date: 2022.09.14
#author: wangzihao
#function: check firewall vip cut

log_dir="/var/log/fwlog"

function get_param() {
    igw_ip=$(crudini --get /opt/fw-cutcheck/fw.ini igw igw_ip)
    igw_user=$(crudini --get /opt/fw-cutcheck/fw.ini igw igw_user)
    igw_pass=$(crudini --get /opt/fw-cutcheck/fw.ini igw igw_pass)
    fw_vips=$(crudini --get /opt/fw-cutcheck/fw.ini $vip)
}

function copy_cutlog() {
    for vip in $(ls /home/fwlog)
        do
            cp $log_dir/$vip/cut.log $log_dir/$vip/cut_old.log
        done      
}

function diff_cutlog_change(){
    for vip in $(ls /home/fwlog)
        do
            diff $log_dir/$vip/cut.log $log_dir/$vip/cut_old.log > /dev/null 2>&1
            if [ $? -ne 0 ]
                then
                    cp $log_dir/$vip/cut.log $log_dir/$vip/cut_old.log
                    igw_reset_vip
            fi
        done
}

function igw_reset_vip(){
    get_param
    for fw_vip in $fw_vips
        do 
            echo reset ip subscriber session ip $fw_vip on $igw_ip
            sshpass -p $igw_pass ssh $igw_user@$igw_ip "reset ip subscriber session ip $fw_vip"
        done
}

main(){
 diff_cutlog_change       
}

copy_cutlog
while :
    do
        main
        sleep 5
    done
