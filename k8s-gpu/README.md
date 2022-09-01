# k8s-gpu 节点扩容
## 节点初始化
- 下载nvidia驱动放到 k8s-gpu/roles/k8s-init/files
- 初始化
```
ansible-playbook -i inventory -t init site.yml
```
- 重启
```
reboot
```
- 安装驱动
```
bash /root/NVIDIA-Linux-x86_64-470.94.run -a -q --ui=none
```
- worker加入k8s
```
ansible-playbook -i inventory -t worker site.yml
```