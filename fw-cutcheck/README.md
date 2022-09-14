# 检测防火墙vip切换后，igw清理mac

## rsyslog配置

```
$ vim /etc/rsyslog.conf

$ModLoad imudp
$UDPServerRun 514

$ModLoad imtcp
$InputTCPServerRun 514

#把下面配置中$IP1替换为fw1的地址，$IP2替换为fw2的地址，$VIP替换为vip的地址，then后面的日志路径要与fw-cutcheck.sh中的$log_dir保持一致

#若有多组fw则写对应多条

if ($fromhost-ip == '$IP1' or $fromhost-ip == '$IP2') and $msg contains '[高可用性] 状态切换' then /var/log/$VIP/cut.log
```

## fw-cutcheck.sh切换检测脚本

- 修改$log_dir与rsyslog配置保持一致

- 调整sleep时间，调整检测间隔

[fw-cutcheck.sh]()

- igw组配置igw地址，igw登陆用户，igw登陆密码

- vip组名称定义为rsyslog配置中的'$VIP'

- 下面配置这组vip下两台fw对应的所有vip，要包括'$VIP'

- 若有多套fw，则定义多个$VIP组

[fw.ini]()


## 配置fw-cutcheck.service

- ExecStart配置为脚本执行绝对路径

[fw-cutcheck.service]()


## 服务使用

- 服务启动
```
$ systemctl start fw-cutcheck
$ systemctl enable fw-cutcheck
```

- 日志路径
```
#服务日志/fw整体日志输出
/var/log/message
```