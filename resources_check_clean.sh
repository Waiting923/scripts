#!/usr/bin/bash


progress(){
    if [ $num -le $resource_num ]
    then
        percent=$(($num * 100 / $resource_num))
        percent_check=$(($percent - $percent_last))
        if [ $percent_check != 0  ]
        then
            rate=#$rate
        else
            rate=$rate
        fi
        if [ $resource_num -ge 100 ]
        then
            printf "progress:[%-100s]%d%%\r" $rate $percent
        else
            printf "progress:[%-"$resource_num"s]%d%%\r" $rate $percent
        fi
    fi
    num=$(($num + 1))
    percent_last=$percent
}


instances_check(){
    echo "Start check instance type resourcs created $mon months ago"
    resource_num=$(openstack server list -f value -c ID --all | wc -l)
    echo "Check in $resource_num instances"
    num=1
    percent_last=0
    rate=''
    for id in `openstack server list -f value -c ID --all`
        do
            progress
            update_time=$(openstack server show -f value -c updated "$id" | awk -F "T" '{print $1}')
            Y=$(echo $update_time | awk -F "-" '{printf $1}')
            M=$[10#$(echo $update_time | awk -F "-" '{printf $2}')]
            D=$[10#$(echo $update_time | awk -F "-" '{printf $3}')]
            NY=$(date +"%Y")
            NM=$[10#$(date +"%m")]
            ND=$[10#$(date +"%d")]
            trove_tag="mysql"
            octavia_tag="amphora"
            if [ $NY -gt $Y ]
            then
                instance_image=$(openstack server show -f value -c image "$id")
                if [[ $instance_image != *$trove_tag* ]] && [[ $instance_image != *$octavia_tag* ]]
                then
                    instance_ip=$(openstack server show -f value -c addresses "$id")
                    instance_name=$(openstack server show -f value -c name "$id")
                    echo "| $id | $instance_name | $update_time | $instance_ip |" >> instances_check_result
                fi
            elif [ $NY -eq $Y ] && [ $(($NM - $M)) -gt $mon ]
            then
                instance_image=$(openstack server show -f value -c image "$id")
                if [[ $instance_image != *$trove_tag* ]] && [[ $instance_image != *$octavia_tag* ]]
                then
                    instance_ip=$(openstack server show -f value -c addresses "$id")
                    instance_name=$(openstack server show -f value -c name "$id")
                    echo "| $id | $instance_name | $update_time | $instance_ip |" >> instances_check_result
                fi
            elif [ $NY -eq $Y ] && [ $(($NM - $M)) -eq $mon ] && [ $D -le $ND ]
            then
                instance_image=$(openstack server show -f value -c image "$id")
                if [[ $instance_image != *$trove_tag* ]] && [[ $instance_image != *$octavia_tag* ]]
                then
                    instance_ip=$(openstack server show -f value -c addresses "$id")
                    instance_name=$(openstack server show -f value -c name "$id")
                    echo "| $id | $instance_name | $update_time | $instance_ip |" >> instances_check_result
                fi
            fi
        done
    echo
    mv instances_check_result instances_check_result-$(date +"%Y-%m-%d")
    echo "Output instances_check_result-$(date +"%Y-%m-%d")"
}


volumes_check(){
    echo "Start check volume type resourcs created $mon months ago and it's dependency snapshot"
    resource_num=$(openstack volume list -f value -c ID --status available --all | wc -l)
    echo "Check in $resource_num volumes"
    num=1
    percent_last=0
    rate=''
    for id in `openstack volume list -f value -c ID --status available --all`
        do
            progress
            update_time=$(openstack volume show -f value -c updated_at "$id" | awk -F "T" '{print $1}')
            Y=$(echo $update_time | awk -F "-" '{printf $1}')
            M=$[10#$(echo $update_time | awk -F "-" '{printf $2}')]
            D=$[10#$(echo $update_time | awk -F "-" '{printf $3}')]
            NY=$(date +"%Y")
            NM=$[10#$(date +"%m")]
            ND=$[10#$(date +"%d")]
            if [ $NY -gt $Y ]
            then
                volume_name=$(openstack volume show -f value -c name "$id")
                echo "| $id | $volume_name | $update_time |" >> volumes_check_result
            elif [ $NY -eq $Y ] && [ $(($NM - $M)) -gt $mon ]
            then
                volume_name=$(openstack volume show -f value -c name "$id")
                echo "| $id | $volume_name | $update_time |" >> volumes_check_result
            elif [ $NY -eq $Y ] && [ $(($NM - $M)) -eq $mon ] && [ $D -le $ND ]
            then
                volume_name=$(openstack volume show -f value -c name "$id")
                echo "| $id | $volume_name | $update_time |" >> volumes_check_result
            fi
        done
    echo
#    mv snapshots_check_result snapshots_check_result-$(date +"%Y-%m-%d")
    mv volumes_check_result volumes_check_result-$(date +"%Y-%m-%d")
    echo "Output volumes_check_result-$(date +"%Y-%m-%d")"
#    echo "Output snapshots_check_result-$(date +"%Y-%m-%d")"
}


#volume_snapshots_check(){
#    snap_num=$(openstack volume snapshot list -f value --volume "$id" | wc -l)
#    if [ $snap_num -gt 0 ]
#    then
#        openstack volume snapshot list -f value -c ID -c Name -c Status --volume "$id" >> snapshots_check_result
#    fi
#}


volume_backups_check(){
    echo "Start check volume backup type resourcs created $mon months ago"
    resource_num=$(openstack volume backup list -f value -c ID --all | wc -l)
    echo "Check in $resource_num volume backups"
    num=1
    percent_last=0
    rate=''
    for id in `openstack volume backup list -f value -c ID --all`
        do
            progress
            update_time=$(openstack volume backup show -f value -c updated_at "$id" | awk -F "T" '{print $1}')
            Y=$(echo $update_time | awk -F "-" '{printf $1}')
            M=$[10#$(echo $update_time | awk -F "-" '{printf $2}')]
            D=$[10#$(echo $update_time | awk -F "-" '{printf $3}')]
            NY=$(date +"%Y")
            NM=$[10#$(date +"%m")]
            ND=$[10#$(date +"%d")]
            if [ $NY -gt $Y ]
            then
                backup_name=$(openstack volume backup show -f value -c name "$id")
                echo "| $id | $backup_name | $update_time |" >> backups_check_result
            elif [ $NY -eq $Y ] && [ $(($NM - $M)) -gt $mon ]
            then
                backup_name=$(openstack volume backup show -f value -c name "$id")
                echo "| $id | $backup_name | $update_time |" >> backups_check_result
            elif [ $NY -eq $Y ] && [ $(($NM - $M)) -eq $mon ] && [ $D -le $ND ]
            then
                backup_name=$(openstack volume backup show -f value -c name "$id")
                echo "| $id | $backup_name | $update_time |" >> backups_check_result
            fi
        done
    echo
    echo "Output backups_check_result-$(date +"%Y-%m-%d")" 
    mv backups_check_result backups_check_result-$(date +"%Y-%m-%d")
}


instances_delete(){
    echo "Start to delete $instances_result_filename instances"
    resource_num=$(cat $instances_result_filename | wc -l)
    echo "Delete $resource_num instances"
    num=1
    percent_last=0
    rate=''
    cat $instances_result_filename  | awk -F "|" '{print $2}' | grep -v ^$ | while read line
        do
            progress
            echo "openstack server delete $line" >> instances_delete_log-$(date +"%Y-%m-%d")
            #openstack server delete $line >> instances_delete_log-$(date +"%Y-%m-%d") 2>&1
        done
    echo
    echo "Log file instances_delete_log-$(date +"%Y-%m-%d")"
}


volumes_delete(){
#    echo "Start to delete $snapshots_result_filename snapshots"
#    resource_num=$(cat $snapshots_result_filename | wc -l)
#    echo "Delete $resource_num snapshots"
#    num=1
#    percent_last=0
#    rate=''
#    cat $snapshots_result_filename | awk -F ' ' '{print $1}' | grep -v ^$ | while read line
#        do
#            progress
#            echo "openstack volume snapshot delete $line" >> snapshots_delete_log-$(date +"%Y-%m-%d")
#            #openstack volume snapshot delete >> snapshots_delete_log-$(date +"%Y-%m-%d") 2>&1
#        done
#    echo
#    echo "Log file snapshots_delete_log-$(date +"%Y-%m-%d")"
    echo "Start to delete $volumes_result_filename volumes"
    resource_num=$(cat $volumes_result_filename | wc -l)
    echo "Delete $resource_num volumes"
    num=1
    percent_last=0
    rate=''
    cat $volumes_result_filename  | awk -F "|" '{print $2}' | grep -v ^$ | while read line
        do
            progress
            echo "openstack volume delete --purge $line" >> volumes_delete_log-$(date +"%Y-%m-%d")
            #openstack volume delete --purge $line >> volumes_delete_log-$(date +"%Y-%m-%d") 2>&1
        done
    echo
    echo "Log file volumes_delete_log-$(date +"%Y-%m-%d")"
}


volume_backups_delete(){
    echo "Start to delete $backups_result_filename backups"
    resource_num=$(cat $backups_result_filename | wc -l)
    echo "Delete $resource_num backups"
    num=1
    percent_last=0
    rate=''
    cat $backups_result_filename | awk -F '|' '{print $2}' | grep -v ^$ | while read line
    do
        progress
        echo "openstack volume backup delete $line" >> backups_delete_log-$(date +"%Y-%m-%d")
        #openstack volume backup delete $line >> backups_delete_log-$(date +"%Y-%m-%d") 2>&1
    done
    echo
    echo "Log file backups_delete_log-$(date +"%Y-%m-%d")"
}


show_usage(){
     cat <<EOF
+------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
|Usage: resources_check_clean [OPTION] <arguments>                                                                                                                       |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
|Options:                                                                                                                                                                |
|   --help, -h                                                                                         {Show usage}                                                      |
|   --mon,-m                                                                                           {Number of months since the resource was created}                 |
|   --instances-check                                                                                  {Only check instance resources}                                   |
|   --volumes-check                                                                                    {Only check volumes and dependent snapshots resources}            |
|   --volume-backups-check                                                                             {Only check volume backups resources}                             |
|   --all-check                                                                                        {Check instance,volume and dependent snapshot resources}          |
|   --instances-delete <result-filename>                                                               {Delete instances}                                                |
|   --volumes-delete <result-filename>                                                                 {Delete volumes and dependent snapshot}                           |
|   --volume-backups-delete <result-filename>                                                          {Delete volume backups}                                           |
|   --all-delete <instance-result-filename> <volume-result-filename> <backup-result-filename>          {Delete instance,volume,backups and dependent snapshot resources} |
|   --clean-all (Only with -m)                                                                         {Check and Delete the old resource}                               |
+------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
EOF
}


main(){
    if [ "$#" -eq 0 ]
    then
        show_usage
    fi

    while [ "$#" -gt 0 ];do
        case $1 in
            (--help|-h)
                show_usage
                exit 0
                ;;
            (--mon|-m)
                mon=$2
                shift 1
                while [[ $1 != -* ]] && [[ $1 ]]
                do
                    shift 1
                done
                if [ -z $mon ]
                then
                    echo "[ERROR] Must specify a number of months !"
                    show_usage
                    exit 1
                fi
                ;;
            (--instances-check)
                check_type=instance
                shift 1
                while [[ $1 != -* ]] && [[ $1 ]]
                do
                    shift 1
                done
                if [[ $1 = "--clean-all" ]]
                then
                    echo "[ERROR] Invalid option !"
                    show_usage
                    exit 1
                fi
                ;;
            (--volumes-check)
                check_type=volume
                shift 1
                while [[ $1 != -* ]] && [[ $1 ]]
                do
                    shift 1
                done
                if [[ $1 = "--clean-all" ]]
                then
                    echo "[ERROR] Invalid option !"
                    show_usage
                    exit 1
                fi
                ;;
            (--volume-backups-check)
                check_type=backup
                shift 1
                while [[ $1 != -* ]] && [[ $1 ]]
                do
                    shift 1
                done
                if [[ $1 = "--clean-all" ]]
                then
                    echo "[ERROR] Invalid option !"
                    show_usage
                    exit 1
                fi
                ;;
            (--all-check)
                check_type=all
                shift 1
                while [[ $1 != -* ]] && [[ $1 ]]
                do
                    shift 1
                done
                if [[ $1 = "--clean-all" ]]
                then
                    echo "[ERROR] Invalid option !"
                    show_usage
                    exit 1
                fi
                ;;
            (--instances-delete)
                delete_type=instance
                instances_result_filename=$2
                shift 1
                while [[ $1 != -* ]] && [[ $1 ]]
                do
                    shift 1
                done
                if [[ $1 = "--clean-all" ]]
                then
                    echo "[ERROR] Invalid option !"
                    show_usage
                    exit 1
                fi
                ;;
            (--volumes-delete)
                delete_type=volume
                volumes_result_filename=$2
                shift 1
                while [[ $1 != -* ]] && [[ $1 ]]
                do
                    shift 1
                done
                if [[ $1 = "--clean-all" ]]
                then
                    echo "[ERROR] Invalid option !"
                    show_usage
                    exit 1
                fi
                ;;
            (--volume-backups-delete)
                delete_type=backup
                backups_result_filename=$2
                shift 1
                while [[ $1 != -* ]] && [[ $1 ]]
                do
                    shift 1
                done
                if [[ $1 = "--clean-all" ]]
                then
                    echo "[ERROR] Invalid option !"
                    show_usage
                    exit 1
                fi
                ;;
            (--all-delete)
                delete_type=all
                instances_result_filename=$2
                volumes_result_filename=$3
                backups_result_filename=$4
                shift 1
                while [[ $1 != -* ]] && [[ $1 ]]
                do
                    shift 1
                done
                if [[ $1 = "--clean-all" ]]
                then
                    echo "[ERROR] Invalid option !"
                    show_usage
                    exit 1
                fi
                ;;
            (--clean-all)
                check_type=all
                delete_type=all
                instances_result_filename=instances_check_result-$(date +"%Y-%m-%d")
                volumes_result_filename=volumes_check_result-$(date +"%Y-%m-%d")
                backups_result_filename=backups_check_result-$(date +"%Y-%m-%d")
                shift 1
                if [[ $1 ]]
                then
                    if [[ $1 = "-m" ]] || [[ $1 = "--mon" ]]
                    then
                        :
                    else
                        echo "[ERROR] Invalid option !"
                        show_usage
                        exit 1
                    fi
                fi
                ;;  
            (*)
                echo "[ERROR] Invalid option !"
                show_usage
                exit 1
                ;;
        esac
    done

    if [ $check_type ]
    then
        if [ -z $mon ]
            then
                echo "[ERROR] Must specify a number of months !"
                show_usage
                exit 1
        fi

        if [ $mon -gt 0 ] 2>/dev/null
        then
            :
        else
            echo "[TYPE ERROR] $mon"
            show_usage
            exit 1
        fi

        if [ $check_type = instance ]
        then
            instances_check
        elif [ $check_type = volume ]
        then
            volumes_check
        elif [ $check_type = backup ]
        then
            volume_backups_check
        elif [ $check_type = all ]
        then
            instances_check
            volumes_check
            volume_backups_check
        fi
    else
        if [ $mon ]
        then
            echo "[ERROR] Must specify check type !"
            show_usage
        fi
    fi
    
    if [ $delete_type ]
    then
        if [ $delete_type = instance ]
        then
            if [[ $instances_result_filename != *instances* ]] || [ -z $instances_result_filename ]
            then
                echo "[ERROR] Please specify the {instances_result_file_name} after --instances-delete !"
                show_usage
                exit 1
            else
                instances_delete
            fi
        elif [ $delete_type = volume ]
        then
            if [[ $volumes_result_filename != *volumes* ]] || [ -z $volumes_result_filename ]
            then
                echo "[ERROR] Please specify the {volume_result_file_name} after --volumes-delete !"
                show_usage
                exit 1
            else
                volumes_delete
            fi
        elif [ $delete_type = backup ]
        then
            if [[ $backups_result_filename != *backups* ]] || [ -z $backups_result_filename ]
            then
                echo "[ERROR] Please specify the {backups_result_file_name} after --volume-backups-delete !"
                show_usage
                exit 1
            else
                volume_backups_delete
            fi
        else
            if [[ $instances_result_filename != *instances* ]] || [ -z $instances_result_filename ] || [[ $volumes_result_filename != *volumes* ]] || [ -z $volumes_result_filename ] || [[ $backups_result_filename != *backups* ]] || [ -z $backups_result_filename ]
            then
                echo "[ERROR] Please specify the {instances_result_file_name} {volume_result_file_name} {backups_result_file_name} after --all-delete !"
                show_usage
                exit 1
            else
                instances_delete
                volumes_delete
                volume_backups_delete
            fi
        fi
    fi
}

main $@
