---
title: github pages-Hexo-CloudFlare免费CDN最佳实践
tags:
  - CDN
  - hexo
  - cloudflare
categories:
  - [hexo]
cover: /img/code/linux.png
top_img: 
date: 2022-06-27 21:14:01
updated: 2022-06-27 21:19:32
description:
keywords:
typora-copy-images-to: ..\img\cut
---

## 一、查看网站是否使用了CDN

执行：nslookup  XXX 命令

```
➜  hexo-blog nslookup clashdingyue.tk
Server:         172.17.112.1
Address:        172.17.112.1#53

Non-authoritative answer:
Name:   clashdingyue.tk
Address: 185.199.110.153
Name:   clashdingyue.tk
Address: 185.199.109.153
Name:   clashdingyue.tk
Address: 185.199.111.153
Name:   clashdingyue.tk
Address: 185.199.108.153
```

```
➜  hexo-blog nslookup wohensha.tk
Server:         172.17.112.1
Address:        172.17.112.1#53

Non-authoritative answer:
Name:   wohensha.tk
Address: 172.67.165.231
Name:   wohensha.tk
Address: 104.21.49.190
```

**两个或两个以上Server IP，则表明使用了CDN，只有一个则表明没有。**

- Github CDN：185.199.110.153、185.199.108.153...
- CloudFlare CDN：172.67.165.231、104.21.49.190



## 二、测试两个CDN哪一个在墙内，速度更好

### CloudFlare CDN

略

### Github CDN

![image-cdn](/img/cut/cdn-test-1.webp)

![image-cdn](/img/cut/cdn-test-2.webp)

(￣▽￣)，半斤八两，感觉Github CDN好点
