#!/usr/bin/python
# -*- coding: utf-8 -*-

import boto
import boto.s3.connection
from concurrent.futures import ThreadPoolExecutor
import ConfigParser
import sys
import threading
import time
import pdb

#pdb.set_trace()
class S3():
    
    def __init__(self):
        self.cfg_file = sys.argv[1]
        self.bucket_name = sys.argv[2]
        self.key_file = sys.argv[3]
        self.thread_num = sys.argv[4]
        self.miss_num = 0
        self.lock = threading.Lock()

    def config_parser(self):
        cf = ConfigParser.ConfigParser()
        cf.read(self.cfg_file)
        self.access_key = cf.get("default", "access_key")
        self.secret_key = cf.get("default", "secret_key")
        host_base = cf.get("default", "host_base")
        self.HOST = str(host_base.split(':')[0])
        self.PORT = 80
        if len(host_base.split(':')) == 2:
            self.PORT = int(host_base.split(':')[1])

    def session(self):
        self.conn = boto.connect_s3(
            aws_access_key_id = self.access_key,
            aws_secret_access_key = self.secret_key,
            host = self.HOST,
            port = self.PORT,
            is_secure=False,
            calling_format = boto.s3.connection.OrdinaryCallingFormat())
    
    def s3thread(self, line, key_num):
        try:
            print(str(key_num + 1) + ': Download ' + line)
            key = self.bucket.get_key(line)
            key.get_contents_to_filename(str(key_num + 1) + ".txt")
        except AttributeError:
            self.lock.acquire()
            with open('s3_get.log', 'a') as log:
                log.write(time.strftime('%Y-%m-%d %H:%M:%S') + '\t' + line + ' not found.\n')
            self.miss_num += 1
            self.lock.release()

    def download_files(self):
        start=time.time()
        self.bucket = self.conn.get_bucket(self.bucket_name)
        with open(self.key_file, 'r') as f:
            line = f.read().splitlines()
        key_num = range(len(line))
        with ThreadPoolExecutor(int(self.thread_num)) as executor:
            executor.map(self.s3thread, line, key_num)
        end=time.time()
        print("ALL: " + str(self.miss_num) + "/" + str(len(line)) + " not found")
        print("Time: " + str(end - start))

if __name__ == "__main__":
    s3 = S3()
    s3.config_parser()
    s3.session()
    #pdb.set_trace()
    s3.download_files()
