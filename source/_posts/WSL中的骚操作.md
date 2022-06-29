---
title: WSL中的骚操作
tags:
  - WSL
  - Linxu
  - typora
categories:
  - [WSL]
cover: 
top_img: 
date: 2022-06-27 14:27:44
updated: 2022-06-27 14:27:44
description:
keywords:
---

## 配置oh-my-zsh

- 启用zsh，并配上一系列插件，可以极大的提升工作效率。

  ```shell
  plugins=(z vi-mode zsh-completions web-search git zsh-autosuggestions zsh-syntax-highlighting rand-quote themes cp)
  ```

  特别是z 、 zsh-completions、zsh-autosuggestions、git都是特别好用的神器。





# 关于Hexo

​		由于Linux出色的命令行终端体验，在Linux中部署Hexo静态博客比Windows方便太多了，在加上一些骚操作，体验非常完美！！！

- 配置一些hexo相关的快捷键（zsh）

  ```shell
  # alias hexo
  alias hd="hexo clean && hexo g && hexo d"
  # alias hs="hexo clean && hexo g && hexo d && hexo s"
  alias hs="hexo clean && hexo g && hexo s"
  alias hnp="hexo new post $1"
  ```

  敲上两个字母，就可以完成hexo的远程部署或者本地调试，体验非常良好。

- 借助Windows和Hexo的互操作性，配置typora用linux命令启动

  ```shell
  # alias windows app
  alias tp='func() { /mnt/d/Typora/Typora.exe $1 &;}; func'
  ```

  敲下tp，就可以直接启动typora.exe，在windows环境下书写markdown了。
