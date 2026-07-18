# wksp

项目工作区管理器 —— 用标签组织跨目录的项目链接。

## 设计

```
$ROOT                        (默认: ~/Documents/WorkSpace)
├── targets/                 默认标签（实体项目目录）
└── tools/                   自定义标签
    └── frida/              嵌套标签
        ├── android/         非项目目录 → 自动共享
        └── a/               项目目录
```

- **标签（tag）** = `$ROOT` 下的目录树
- **项目** = `wksp <名称>` 注册，数据存 `$ROOT/<标签>/<名称>/`
- **本地镜像** = `当前目录/<名称>/<标签>/` → symlink 到 `$ROOT`
- **共享项目** = `-s` 标记，`$ROOT` 目录保留，被同标签下其他项目自动链接
- **非项目目录** 自动成为共享资源

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/resetself/workspace/main/install.sh | sh
```

或从源码编译。

## 命令

```
wksp                        列出所有项目
wksp <名称>                 注册当前目录（targets 标签）
wksp <名称> @标签,...        指定标签
wksp <名称> -s [@标签,...]   注册为共享项目
wksp <名称> -l               列出项目所属标签
wksp <名称> -k [...]         保留已有本地目录
wksp tag                    列出所有标签
wksp tag <名称,...>          创建标签，或列出项目
wksp tag <名称> -d           删除空标签
wksp clean                  清除本地目录 + 空 $ROOT 目录
wksp path [<目录>]           查看/设置根路径
```

## 示例

```bash
% wksp myapp
# → $ROOT/targets/myapp/
# → ./myapp/targets → $ROOT/targets/myapp

% wksp frida -s @tools/frida
# → 共享项目，不创建 targets/
# → $ROOT/tools/frida/frida/

% wksp test @tools/frida
# → ./test/tools/frida/
#     ├── self   → $ROOT/tools/frida/test
#     └── frida  → $ROOT/tools/frida/frida   (自动链接共享)

% wksp
 frida  ~/code/frida [shared]
*test   ~/code/test

% wksp test -l
targets
tools/frida

% wksp clean
# → 清除本地目录 + 空 $ROOT 目录，state 保留

% wksp test
# → 从 state 重建本地目录
```

## 状态

`~/.config/wksp/state.json`：

```json
{
  "root": "/home/me/Documents/WorkSpace",
  "active": "test",
  "projects": [
    {"name":"frida","local":"~/code/frida","tags":["tools/frida"],"shared":true},
    {"name":"test","local":"~/code/test","tags":["targets","tools/frida"]}
  ]
}
```
