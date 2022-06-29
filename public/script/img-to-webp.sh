#!/bin/zsh

# 创建备份文件夹
mkdir "bak"

echo $1
# 利用ls和正则获取当前目录下的所有图片路径存入数组
echo $1/*.{png,jpg}
path="$1/*.{png,jpg}"
echo $path
echo "================================="
#images=$(ls "$1/*.{png,jpg}")
images=`ls $path`

for image in $images
# for image in  `eval ls $1/*.{png,jpg}`
do
  echo $image
  # -q 90 指定转换质量，经试验这个值效果和压缩率都不错
  cwebp $image -q 90 -o ${image%.*}.webp
  # mv $image ./bak/$image
done
