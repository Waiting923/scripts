#encoding=utf-8
#!/usr/bin/env python

import os
import MySQLdb
import ConfigParser


def get_config():
    try:
        conf = ConfigParser.ConfigParser()
        conf.read('gpu.conf')
    except Exception as e:
        print e.message
    finally:
        return conf

def connect_db():
    try:
        conf = get_config()
        conn = MySQLdb.connect(
            host = conf.get("cmp_east_db", "host"),
            user = conf.get("cmp_east_db", "user"),
            passwd = conf.get("cmp_east_db", "passwd"),
            db = conf.get("cmp_east_db", "dbname"),
            port =  int(conf.get("cmp_east_db", "port")),
            charset = 'utf8'
            )
        return conn
    except Exception as e:
        print e.message
        raise

def cmp_db():
    conn = connect_db()
    return conn

