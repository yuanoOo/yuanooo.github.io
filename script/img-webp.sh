#!/usr/bin/env bash

# 创建备份文件夹
mkdir "bak"

# 利用ls和正则获取当前目录下的所有图片路径存入数组
images=$(ls *.{png,jpg})

for image in $images
do
  echo $image
  # -q 90 指定转换质量，经试验这个值效果和压缩率都不错
  cwebp $image -q 90 -o ${image%.*}.webp
  # mv $image ./bak/$image
done
