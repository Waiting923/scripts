#!/bin/bash
AGENT_2='169606c4-c0a7-4cd8-ac8a-627ffee42e4e'
AGENT_1='363f6c14-9e8d-45b9-9c8d-b376432e5dcb'
LOCAL_AGENT=$AGENT_1
REMOTE_AGENT=$AGENT_2
ROUTERS=$(cat ./router-list)

function ha_link_set() {
    DEVICE=`sudo ip netns exec qrouter-$1 ip a | grep ": ha-" | grep -o "ha-.\{11\}"`
    sudo ip netns exec qrouter-$1 ip link set dev $DEVICE down
    sleep 10
}

function move_active() {
    if [[ $REMOTE_AGENT == $STANDBY_HOST ]]
    then
      echo "err: $1 need choose another host to migrate"
    else
      ha_link_set $1
      neutron l3-agent-router-remove $LOCAL_AGENT $1
      neutron l3-agent-router-add $REMOTE_AGENT $1
    fi
}

function move_standby() {
    if [[ $REMOTE_AGENT == $ACTIVE_HOST ]]
    then
      echo "err: $1 need choose another host to migrate"
    else
      neutron l3-agent-router-remove $LOCAL_AGENT $1
      neutron l3-agent-router-add $REMOTE_AGENT $1
    fi
}

function operation() {
    neutron l3-agent-list-hosting-router $1 -f value -c id -c ha_state > RESULT
    RESULT_ACTIVE=$(cat RESULT | grep $LOCAL_AGENT | grep -o "active")
    RESULT_STANDBY=$(cat RESULT | grep $LOCAL_AGENT | grep -o "standby")
    ACTIVE_HOST=$(cat RESULT | grep active | awk '{print $1}')
    STANDBY_HOST=$(cat RESULT | grep standby | awk '{print $1}')
    if [ $RESULT_ACTIVE ];then
        echo "active"
        move_active $1
    elif [ $RESULT_STANDBY ];then
        echo "standby"
        move_standby $1
    else
        echo "router not here"
    fi
}


TMP=0
for i in $ROUTERS;do
    TMP=$[TMP+1]
    echo $TMP
    echo $i
    operation $i
    if [ $TMP -eq 100 ];then
        break
    fi
done
