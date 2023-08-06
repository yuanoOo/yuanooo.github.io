---
title: hexo+freenom+cloudflare遇到的一些坑
tags:
  - hexo
  - github pages
  - CFW
categories:
  - hexo
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
keywords: freenom、CloudFlare、clash
abbrlink: 6631
date: 2022-06-27 11:30:32
updated: 2022-06-27 11:30:32
cover:
description:
---



#### 使用CloudFlare进行DNS解析，并启用CloudFlare的代理和CDN后，github pages无法访问

> ​		原因就是 CloudFlare到 GitHub Pages这段 回源没有采用 TLS访问，解决的办法也很简单，在 CloudFlare中找到 SSL/TLS中的 概述，把默认的 灵活（加密浏览器与 Cloudflare 之间的流量）改为 完全（端到端加密，使用服务器上的自签名证书）即可。



#### CFW（Clash For Windows）TUN 模式

> 对于不遵循系统代理的软件，TUN 模式可以接管其流量并交由 CFW 处理，在 Windows 中，TUN 模式性能比 TAP 模式好

> **NOTICE**

> 近期大部分浏览器默认已经开启“**安全 DNS**”功能，此功能会影响 TUN 模式劫持 DNS 请求导致反推域名失败，请在浏览器设置中关闭此功能以保证 TUN 模式正常运行



