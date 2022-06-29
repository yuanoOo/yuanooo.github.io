---
title: 从github恢复备份hexo博客By hexo-git-backup
tags:
  - 'hexo'
categories:
  - [hexo]
top_img: 'linear-gradient(20deg, #0062be, #925696, #cc426e, #fb0347)'
date: 2022-06-29 13:54:12
updated: 2022-06-29 13:54:12
cover:
description:
keywords:
---



​		利用hexo + github pages构建静态博客网站，hexo发布到github上的内容是渲染过后的文件。而我们自己写的markdown文件并没有推送到github上面，因此如果发生电脑挂掉、磁盘挂掉等意外，我们的.md源文件以及我们的博客配置文件就会丢失。丢失后要想还原回去，就需要费好大力气了。

​		因此我们需要备份源数据，并且最好每次部署博客的时候，就自动进行备份，而不需要再手动去备份。



## 利用hexo-git-backup插件备份源文件

- 1、安装hexo-git-backup插件

  ```
  $ npm install hexo-git-backup --save
  ```

- 2、配置插件，同步源数据到github仓库

  **强烈建议：备份到博客所在的同一个git仓库的不同分支，方便管理，下面是备份到hexo分支**

  > 编辑hexo的配置文件_config.yml，添加需要备份到仓库

  ```yml
  # 备份插件：hexo-git-backup
  backup:
      type: git
      repository:
         github: git@github.com:xxxxx.git,hexo
  ```

- 3、hexo根目录执行hexo b命令，即可完成备份



##  每次更新博客后，自动进行备份

- 使用windows的同学，强烈建议(￣▽￣)"开启linux子系统WSL，在WSL中部署Hexo：https://poxiao.tk/2022/06/WSL%E4%B8%AD%E7%9A%84%E9%AA%9A%E6%93%8D%E4%BD%9C/

### 利用shell alias，部署后自动备份

- 编辑zsh的配置文件~/.zshrc，添加别名alias：

```shell
alias hd="hexo clean && hexo g && hexo d && hexo b"
```

- 每次要更新博客进行部署的时候，直接执行`hd`命令，就会自动完成部署和备份的工作。

  

  
