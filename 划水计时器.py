#!/usr/bin/python3
# -*- coding: UTF-8 -*-
#author: wangdengdeng
import tkinter as tk
import time
import tkinter.messagebox
from threading import Thread

top = tk.Tk()
start=False

def start_clock():
    prtext = tk.Text(top, width=30, height=1)
    global start
    if start == False:
        start = True
        prtext.pack()
        while start == True:
            prtext.delete(1.0, tk.END)
            prtext.insert(tk.END, chong_clock()[0])
            prtext.see(tk.END)
            prtext.update()
            time.sleep(60 - chong_clock()[1][5])

def chong_clock():
    now = time.localtime()
    if now[3] == 18 and now[4] == 0:
        result=str('冲冲冲')
    elif now[3] >= 12 and now[3] < 18:
        result=str('还得划' + str(17 - now[3]) + '小时' + str(60 - now[4]) + '分钟。')
    elif now[3] >= 9 and now[3] < 12:
        result=str('还有' + str(12 - now[3]) + '小时' + str(60 - now[4]) + '分钟吃饭。')
    else:
        result=str('已经义务劳动' + str((now[3]) - 18) + '小时' + str(now[4]) + '分钟。')
    return result, now
    time.sleep(60 - now[5])

def ask_recheck():
    if tkinter.messagebox.askyesno(title='FBI WARRNING!!!', message='运行时间加速器可能会导致所处的时间线混乱，请谨慎决定是否使用。'):
        tkinter.messagebox.showerror(title='嘻嘻嘻', message='你在想屁吃，憨批。')
    else:
        tkinter.messagebox.showinfo(title='啧啧', message='可惜。')

def thread_it():
    t = Thread(target=start_clock)
    t.setDaemon(True)
    t.start()


def main():
    lb = tk.Label(top, text='富强 明主 文明 和谐 自由 平等 公正 法治 爱国 敬业 诚信 友善', bg='white', fg='red', font=('Arial', 10), width=200, height=2)
    bt_start = tk.Button(top, text='开始划', font=('Arial', 10), width=10, height=1, command=thread_it)
    menubar = tk.Menu(top)
    filemenu = tk.Menu(menubar, tearoff=0)
    menubar.add_cascade(label='机密', menu=filemenu)
    filemenu.add_command(label='下班加速器', command=ask_recheck)
    top.config(menu=menubar)
    top.title('划水计时器')
    top.geometry('400x100')
    lb.pack(side='top')
    bt_start.pack(side='bottom')
    top.mainloop()

if __name__ == '__main__':
    main()