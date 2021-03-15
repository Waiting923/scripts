#!/usr/bin/python
# -*- coding: utf-8 -*-

import boto
import boto.s3.connection
import ConfigParser
import sys
import time
import pdb

#pdb.set_trace()
class S3():
    
    def __init__(self):
        self.cfg_file = sys.argv[1]
        self.bucket_name = sys.argv[2]
        self.key_file = sys.argv[3]

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
    
    def download_files(self):
        bucket = self.conn.get_bucket(self.bucket_name)
        with open(self.key_file, 'r') as f:
            get_num = 1
            file_num = 1
            for line in f.readlines():
                line = line.strip()
                key = bucket.get_key(line)
                print(str(file_num) +  ": Download " + line)
                file_num += 1
                try:
                    key.get_contents_to_filename(str(get_num) + ".txt")
                except AttributeError:
                    with open('s3_get.log', 'a') as log:
                        log.write(time.strftime('%Y-%m-%d %H:%M:%S') + '\t' + line + ' not found.\n')
                        print(line + ' not found.')
                else:
                    get_num += 1
            print ("ALL: Get " + str(get_num - 1) + " files.")

if __name__ == "__main__":
    #pdb.set_trace()
    s3 = S3()
    s3.config_parser()
    s3.session()
    s3.download_files()
