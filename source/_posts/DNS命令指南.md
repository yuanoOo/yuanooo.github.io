---
title: DNS命令指南。怎么验证是否遭遇DNS污染？查看域名是否解析成功？
tags:
  - dns
categories:
  - - dns
  - - linux
keywords: DNS
abbrlink: 6111
date: 2022-06-27 18:24:43
updated: 2022-06-27 18:24:43
cover:
top_img:
description:
---

# DNS指南

## 查询DNS服务器

- linux：```cat /etc/resolv.conf``` 

- windows: ipconfig /all

  ```
  PS C:\Users\sssbb> ipconfig /all
  
  Windows IP 配置
  
     主机名  . . . . . . . . . . . . . : DESKTOP-KD33OT8
     主 DNS 后缀 . . . . . . . . . . . :
     节点类型  . . . . . . . . . . . . : 混合
     IP 路由已启用 . . . . . . . . . . : 否
     WINS 代理已启用 . . . . . . . . . : 否
  
  未知适配器 Clash:
  
     连接特定的 DNS 后缀 . . . . . . . :
     描述. . . . . . . . . . . . . . . : Clash Tunnel
     物理地址. . . . . . . . . . . . . :
     DHCP 已启用 . . . . . . . . . . . : 否
     自动配置已启用. . . . . . . . . . : 是
     IPv4 地址 . . . . . . . . . . . . : 198.18.0.1(首选)
     子网掩码  . . . . . . . . . . . . : 255.255.0.0
     默认网关. . . . . . . . . . . . . :
     DNS 服务器  . . . . . . . . . . . : 198.18.0.2
     TCPIP 上的 NetBIOS  . . . . . . . : 已启用
  
  无线局域网适配器 本地连接* 1:
  
     媒体状态  . . . . . . . . . . . . : 媒体已断开连接
     连接特定的 DNS 后缀 . . . . . . . :
     描述. . . . . . . . . . . . . . . : Microsoft Wi-Fi Direct Virtual Adapter
     物理地址. . . . . . . . . . . . . : 1A-4F-32-F7-BE-99
     DHCP 已启用 . . . . . . . . . . . : 是
     自动配置已启用. . . . . . . . . . : 是
  
  无线局域网适配器 本地连接* 10:
  
     媒体状态  . . . . . . . . . . . . : 媒体已断开连接
     连接特定的 DNS 后缀 . . . . . . . :
     描述. . . . . . . . . . . . . . . : Microsoft Wi-Fi Direct Virtual Adapter #2
     物理地址. . . . . . . . . . . . . : 1A-4F-32-F7-B6-99
     DHCP 已启用 . . . . . . . . . . . : 是
     自动配置已启用. . . . . . . . . . : 是
  
  无线局域网适配器 WLAN:
  
     连接特定的 DNS 后缀 . . . . . . . :
     描述. . . . . . . . . . . . . . . : Dell Wireless 1830 802.11ac
     物理地址. . . . . . . . . . . . . : 18-4F-32-F7-BE-99
     DHCP 已启用 . . . . . . . . . . . : 是
     自动配置已启用. . . . . . . . . . : 是
     本地链接 IPv6 地址. . . . . . . . : fe80::5d17:d6:2915:d43c%3(首选)
     IPv4 地址 . . . . . . . . . . . . : 192.168.31.250(首选)
     子网掩码  . . . . . . . . . . . . : 255.255.255.0
     获得租约的时间  . . . . . . . . . : 2022年6月27日 13:00:31
     租约过期的时间  . . . . . . . . . : 2022年6月28日 1:00:34
     默认网关. . . . . . . . . . . . . : 192.168.31.1
     DHCP 服务器 . . . . . . . . . . . : 192.168.31.1
     DHCPv6 IAID . . . . . . . . . . . : 51924786
     DHCPv6 客户端 DUID  . . . . . . . : 00-01-00-01-2A-3F-FD-A1-18-4F-32-F7-BE-99
     DNS 服务器  . . . . . . . . . . . : 192.168.31.1
     TCPIP 上的 NetBIOS  . . . . . . . : 已启用
  
  以太网适配器 蓝牙网络连接:
  
     媒体状态  . . . . . . . . . . . . : 媒体已断开连接
     连接特定的 DNS 后缀 . . . . . . . :
     描述. . . . . . . . . . . . . . . : Bluetooth Device (Personal Area Network)
     物理地址. . . . . . . . . . . . . : 18-4F-32-F7-BE-9A
     DHCP 已启用 . . . . . . . . . . . : 是
     自动配置已启用. . . . . . . . . . : 是
  
  以太网适配器 vEthernet (WSL):
  
     连接特定的 DNS 后缀 . . . . . . . :
     描述. . . . . . . . . . . . . . . : Hyper-V Virtual Ethernet Adapter
     物理地址. . . . . . . . . . . . . : 00-15-5D-5C-2A-EA
     DHCP 已启用 . . . . . . . . . . . : 否
     自动配置已启用. . . . . . . . . . : 是
     本地链接 IPv6 地址. . . . . . . . : fe80::d82d:5ba6:7b4b:9023%40(首选)
     IPv4 地址 . . . . . . . . . . . . : 172.17.112.1(首选)
     子网掩码  . . . . . . . . . . . . : 255.255.240.0
     默认网关. . . . . . . . . . . . . :
     DHCPv6 IAID . . . . . . . . . . . : 671094109
     DHCPv6 客户端 DUID  . . . . . . . : 00-01-00-01-2A-3F-FD-A1-18-4F-32-F7-BE-99
     DNS 服务器  . . . . . . . . . . . : fec0:0:0:ffff::1%1
                                         fec0:0:0:ffff::2%1
                                         fec0:0:0:ffff::3%1
     TCPIP 上的 NetBIOS  . . . . . . . : 已启用
  ```

   

## 查看域名是否解析成功：

- 可以直接ping域名，也可以使用nslookup命令（NameServer Lookup）

- 在用 nslookup 查询一个域名时，可能会看到有“非权威应答” 的提示，非权威应答（Non-authoritative answer）意味着answer来自于其他服务器的缓存，而不是权威的服务器（就是该域名配置的DNS解析服务器，如果你的域名解析配置在CF的DNS上，则权威服务器，就是CF的DNS）。缓存会根据 ttl（Time to Live）的值定时的进行更新。

  ```
  ➜  hexo-blog nslookup wohensha.tk 8.8.8.8
  Server:         8.8.8.8
  Address:        8.8.8.8#53
  
  Non-authoritative answer:
  Name:   wohensha.tk
  Address: 104.21.49.190
  Name:   wohensha.tk
  Address: 172.67.165.231
  Name:   wohensha.tk
  Address: 2606:4700:3031::ac43:a5e7
  Name:   wohensha.tk
  Address: 2606:4700:3031::6815:31be
  ```

- sds查找权威名字服务器

  ```
  ➜  hexo-blog nslookup -ty=ns clashdingyue.tk
  Server:         172.17.112.1
  Address:        172.17.112.1#53
  
  Non-authoritative answer:
  clashdingyue.tk nameserver = ns04.freenom.com.
  clashdingyue.tk nameserver = ns02.freenom.com.
  clashdingyue.tk nameserver = ns01.freenom.com.
  clashdingyue.tk nameserver = ns03.freenom.com.
  
  Authoritative answers can be found from:
  
  ➜  hexo-blog nslookup -ty=ns clashdingyue.tk ns04.freenom.com
  Server:         ns04.freenom.com
  Address:        104.155.29.241#53
  
  clashdingyue.tk nameserver = ns04.freenom.com.
  clashdingyue.tk nameserver = ns03.freenom.com.
  clashdingyue.tk nameserver = ns02.freenom.com.
  clashdingyue.tk nameserver = ns01.freenom.com.
  ```



# 一些小技巧

### 怎么验证是否遭遇DNS污染？

​		**DNS污染**即网域服务器缓存污染，又称域名服务器缓存投毒，是指一些刻意制造或无意中制造出来的域名服务器数据包，把域名指往不正确的IP地址。一般来说，在互联网上都有可信赖的网域服务器，但为减低网络上的流量压力，一般的域名服务器都会把从上游的域名服务器获得的解析记录暂存起来，待下次有其他机器要求解析域名时，可以立即提供服务。一旦有关网域的局域域名服务器的缓存受到污染，就会把网域内的计算机导引往错误的服务器。

   	我们应该怎么去验证自己域名是否遭遇DNS污染呢？输入命令dig +trace clashdingyue.tk（您自己需要检测域名）。**如果域名未被污染我们会得到权威DNS的应答**，如下所示:

```cobol
➜  hexo-blog dig +trace clashdingyue.tk
;; Warning: Client COOKIE mismatch

; <<>> DiG 9.16.1-Ubuntu <<>> +trace clashdingyue.tk
;; global options: +cmd
.                       200     IN      NS      g.root-servers.net.
.                       200     IN      NS      j.root-servers.net.
.                       200     IN      NS      d.root-servers.net.
.                       200     IN      NS      h.root-servers.net.
.                       200     IN      NS      m.root-servers.net.
.                       200     IN      NS      k.root-servers.net.
.                       200     IN      NS      a.root-servers.net.
.                       200     IN      NS      i.root-servers.net.
.                       200     IN      NS      b.root-servers.net.
.                       200     IN      NS      f.root-servers.net.
.                       200     IN      NS      c.root-servers.net.
.                       200     IN      NS      l.root-servers.net.
.                       200     IN      NS      e.root-servers.net.
;; Received 443 bytes from 172.17.112.1#53(172.17.112.1) in 840 ms

tk.                     172800  IN      NS      a.ns.tk.
tk.                     172800  IN      NS      b.ns.tk.
tk.                     172800  IN      NS      c.ns.tk.
tk.                     172800  IN      NS      d.ns.tk.
tk.                     86400   IN      NSEC    tkmaxx. NS RRSIG NSEC
tk.                     86400   IN      RRSIG   NSEC 8 1 86400 20220710050000 20220627040000 47671 . HwO7QYzt3lI0k1w10qjM7oUf0B71yWgbUu9yCPcUdUng1icIu0lXSebp thdZpvOpLrjTE461RZJSlYaKIPavphtjpQHnUVxlH3Qznw9cBhql9Qnx cEtMo7vlCkCRST9sojkQxRqFW1oQMOoGG1j+SWpejRYwaudILcDCl0bP 4nPu1t5KmGR3Q8DKKO075O69w8MTauU+yfOsxEPvYgmHGzIyU7pBMWyt sUA+5ZpnrQ+0KLcXxnpUPQpBb55RlO1PhRqlJ9bT8qfYfvT+QUL5alwl xJxyZVcLTlGrpggW76yWjN3gq3zzynmd3D5cGeFQSon1+qMR5i6LoQix b4Jycg==
;; Received 602 bytes from 193.0.14.129#53(k.root-servers.net) in 350 ms

clashdingyue.tk.        300     IN      NS      ns01.freenom.com.
clashdingyue.tk.        300     IN      NS      ns02.freenom.com.
clashdingyue.tk.        300     IN      NS      ns03.freenom.com.
clashdingyue.tk.        300     IN      NS      ns04.freenom.com.
;; Received 131 bytes from 194.0.41.1#53(d.ns.tk) in 330 ms

clashdingyue.tk.        3600    IN      A       185.199.108.153
clashdingyue.tk.        3600    IN      A       185.199.110.153
clashdingyue.tk.        3600    IN      A       185.199.109.153
clashdingyue.tk.        3600    IN      A       185.199.111.153
clashdingyue.tk.        300     IN      NS      ns03.freenom.com.
clashdingyue.tk.        300     IN      NS      ns04.freenom.com.
clashdingyue.tk.        300     IN      NS      ns02.freenom.com.
clashdingyue.tk.        300     IN      NS      ns01.freenom.com.
;; Received 248 bytes from 54.171.131.39#53(ns01.freenom.com) in 470 ms
```

**如果域名被污染会直接到的一个IP，并不会向权威DNS请求。**如下所示：

```
➜  hexo-blog dig +trace google.com
;; Warning: Client COOKIE mismatch

; <<>> DiG 9.16.1-Ubuntu <<>> +trace google.com
;; global options: +cmd
.                       1450    IN      NS      f.root-servers.net.
.                       1450    IN      NS      k.root-servers.net.
.                       1450    IN      NS      d.root-servers.net.
.                       1450    IN      NS      j.root-servers.net.
.                       1450    IN      NS      l.root-servers.net.
.                       1450    IN      NS      m.root-servers.net.
.                       1450    IN      NS      h.root-servers.net.
.                       1450    IN      NS      i.root-servers.net.
.                       1450    IN      NS      e.root-servers.net.
.                       1450    IN      NS      c.root-servers.net.
.                       1450    IN      NS      a.root-servers.net.
.                       1450    IN      NS      b.root-servers.net.
.                       1450    IN      NS      g.root-servers.net.
;; Received 443 bytes from 172.17.112.1#53(172.17.112.1) in 840 ms

google.com.             60      IN      A       8.7.198.46
;; Received 54 bytes from 192.33.4.12#53(c.root-servers.net) in 20 ms
```

