#!/usr/bin/python
#-*- coding: utf-8 -*-
import ConfigParser
from novaclient import client
from keystoneauth1 import session
from keystoneauth1.identity import v3
from os import getenv
import pdb
import sys


class gpu_resources():
    
    def __init__(self):
        self.OS_USER_DOMAIN_NAME = getenv('OS_USER_DOMAIN_NAME')
        self.OS_USERNAME = getenv('OS_USERNAME')
        self.OS_PASSWORD = getenv('OS_PASSWORD')
        self.OS_PROJECT_DOMAIN_NAME = getenv('OS_PROJECT_DOMAIN_NAME')
        self.OS_PROJECT_NAME = getenv('OS_PROJECT_NAME')
        self.OS_AUTH_URL = getenv('OS_AUTH_URL')
        self.OS_REGION_NAME = getenv('OS_REGION_NAME')
        self.gpu_type = sys.argv[1]
    
    def cfg(self):
        conf = ConfigParser.ConfigParser()
        conf.read('gpu.conf')
        self.flavor_ids = conf.get("flavor", self.gpu_type + "_flavor").split(',')
        self.aggregate_id = int(conf.get("aggregates", self.gpu_type + "_aggregates"))


    def keystone_auth(self):
        auth = v3.Password(user_domain_name=self.OS_USER_DOMAIN_NAME,
                           username=self.OS_USERNAME,
                           password=self.OS_PASSWORD,
                           project_domain_name=self.OS_PROJECT_DOMAIN_NAME,
                           project_name=self.OS_PROJECT_NAME,
                           auth_url=self.OS_AUTH_URL)
        self.sess = session.Session(auth=auth)

    def nova_client(self):
        self.nova = client.Client('2.1', session=self.sess, region_name=self.OS_REGION_NAME)

    def get_hosts(self):
        self.gpu_hosts = self.nova.aggregates.get(self.aggregate_id).hosts

    def find_instances(self):
        all_gpu_num = 0
        for gpu_host in self.gpu_hosts:
            flavor_gpu_num = 1
            sum_host_gpu_num = 0
            print("-------\n{:<}".format(gpu_host))
            for flavor_id in self.flavor_ids:
                instance_list = self.nova.servers.list(search_opts={'flavor':flavor_id, 'all_tenants':True, 'host':str(gpu_host)})
                instance_list = [instance for instance in instance_list if instance.status != 'ERROR']
                if len(instance_list) > 0:
                    for instance in instance_list:
                        print("Flavor:{:<} ID:{:<} Status:{:<} Name:{:<}".format(flavor_id, instance.id, instance.status ,instance.name))
                host_gpu_num = len(instance_list) * flavor_gpu_num
                sum_host_gpu_num += host_gpu_num
                all_gpu_num += host_gpu_num
                flavor_gpu_num = flavor_gpu_num * 2
            print("used {:<}\n".format(sum_host_gpu_num))
        print("ALL USED: " + str(all_gpu_num))

    def main(self):
        #pdb.set_trace()
        self.cfg()
        self.keystone_auth()
        self.nova_client()
        self.get_hosts()
        self.find_instances()

if __name__ == '__main__':
    gpu = gpu_resources()
    gpu.main()
