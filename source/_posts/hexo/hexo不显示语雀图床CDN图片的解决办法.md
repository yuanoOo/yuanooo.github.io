---
title: hexo不显示语雀图床CDN图片的解决办法
tags:
  - 'hexo'
categories:
  - [hexo]
top_img: 
date: 2022-07-02 11:22:17
updated: 2022-07-02 11:22:17
cover:
description:
keywords:
---

# 前言

在语雀中写了一点东西，于是想着一起发到hexo上面，本地Typora显示完全没有问题，但是打开博客一看，图片全挂了！！！

于是复制图片链接到浏览器上，竟然是直接下载，什么情况，直接懵逼。又试了试正常显示的图片，是在浏览器打开的。Google了半天，原来是语雀的防盗链搞得。



# 解决方法



### 1、在Hexo的.md文件加上`<meta name="referrer" content="no-referrer" />`

- 可以在post模板中直接加上,就像下面这样，每次`hexo new post`创建都会自动加上，就不用每次都添加了。

``` markdown
---
title: 
tags:
  - ''
categories:
  - []
top_img: 
date: 
updated: 
cover:
description:
keywords:
---
  
<meta name="referrer" content="no-referrer" />
```



### 2、以`<img src="xxxx" referrerpolicy="no-referrer">`的形式插入图片

- 太麻烦了,每次都要设置`referrerpolicy="no-referrer"`



### 3、在html模版的头信息中添加`<meta name="referrer" content="no-referrer" />`

#### 1、butterfly主题

在hexo-theme-butterfly/layout/includes目录下的head.pug文件中添加`meta(name="referrer" content="no-referrer")`

```typescript
meta(charset='UTF-8')
meta(http-equiv="X-UA-Compatible" content="IE=edge")
meta(name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no")
title= tabTitle
if pageKeywords
  meta(name="keywords" content=pageKeywords)
meta(name="author" content=pageAuthor)
meta(name="copyright" content=pageCopyright)
meta(name ="format-detection" content="telephone=no")
meta(name="theme-color" content=themeColor)

meta(name="referrer" content="no-referrer")
```



# 参考资料

- https://github.com/x-cold/yuque-hexo/issues/41

