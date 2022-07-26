#!/usr/bin/python
#date: 2021.04.01
#author: wangzihao
#function: statistical resources for gpu
#-*- coding: utf-8 -*-
import argparse
import ConfigParser
from novaclient import client
from keystoneauth1 import session
from keystoneauth1.identity import v3
from mysql_connect import *
from os import getenv
import pdb


class gpu_resources():
 
    def __init__(self):
        self.OS_USER_DOMAIN_NAME = getenv('OS_USER_DOMAIN_NAME')
        self.OS_USERNAME = getenv('OS_USERNAME')
        self.OS_PASSWORD = getenv('OS_PASSWORD')
        self.OS_PROJECT_DOMAIN_NAME = getenv('OS_PROJECT_DOMAIN_NAME')
        self.OS_PROJECT_NAME = getenv('OS_PROJECT_NAME')
        self.OS_AUTH_URL = getenv('OS_AUTH_URL')
        self.OS_REGION_NAME = getenv('OS_REGION_NAME')

    def cfg(self):
        conf = ConfigParser.ConfigParser()
        conf.read('gpu.conf')
        self.flavor_ids = conf.get("flavor", self.gpu_type + "_flavor").split(',')
        self.aggregate_id = conf.getint("aggregates", self.gpu_type + "_aggregates")
        self.total_num = conf.getint("total", self.gpu_type + "_num")

    def get_args(self):
        parser = argparse.ArgumentParser()
        parser.add_argument("gpu_type", help="include RTX1080,P100,V100S")
        args = parser.parse_args()
        self.gpu_type = args.gpu_type

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
            print(format(gpu_host, "-^100"))
            for flavor_id in self.flavor_ids:
                instance_list = self.nova.servers.list(search_opts={'flavor':flavor_id, 'all_tenants':True, 'host':str(gpu_host)})
                instance_list = [instance for instance in instance_list if instance.status != 'ERROR']
                if len(instance_list) > 0:
                    for instance in instance_list:
                        customer_info = self.get_vm_info(uuid = instance.id)
                        print("Flavor:{:<} ID:{:<} Status:{:<} Name:{:<} VPP_ID:{:<} Customer:{:<}".format(flavor_id, instance.id, instance.status ,instance.name, customer_info['vpp_id'], customer_info['customer'].encode('utf8') ))
                host_gpu_num = len(instance_list) * flavor_gpu_num
                sum_host_gpu_num += host_gpu_num
                all_gpu_num += host_gpu_num
                flavor_gpu_num = flavor_gpu_num * 2
            print("used {:<}\n".format(sum_host_gpu_num))
        print("ALL USED: " + str(all_gpu_num) + "/" + str(self.total_num))

    def get_vm_info(self, uuid=None):
        query = "select a.customer_id from yvs_server a where a.res_id in ('%s')" % uuid
        conn = cmp_db()
        cur = conn.cursor()
        cur.execute(query)
        result = cur.fetchall()
        conn.commit()
        cur.close()
        vm = {}
        vm['customer'],vm['vpp_id'] = self.get_custom_info(customer_id = result[0])
        return vm

    def get_custom_info(self, customer_id = None):
        query = "select name,vpp_id from cmp2_vp.vpp_crm_customer where id in ('%s')" % customer_id
        conn = cmp_db()
        cur = conn.cursor()
        cur.execute(query)
        result = cur.fetchall()
        conn.commit()
        cur.close()
        for t in result:
            return t[0],t[1]

    def main(self):
        #pdb.set_trace()
        self.get_args()
        self.cfg()
        self.keystone_auth()
        self.nova_client()
        self.get_hosts()
        self.find_instances()

if __name__ == '__main__':
    gpu = gpu_resources()
    gpu.main()
