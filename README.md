# wksp

project workspace manager — link directories across toolkits.

## concept

```
$ROOT                        (default: ~/Documents/WorkSpace)
├── targets/                 default toolkit (real project dirs)
└── tools/                   wksp tag tools → custom toolkit
    ├── frida/               nested toolkit
    │   ├── android/         non-project dir → auto-shared
    │   └── a/               project dir
    └── b/                   project dir
```

- **toolkit (tag)** = a directory tree under `$ROOT`
- **project** = registered with `wksp <name>`, data in `$ROOT/<tag>/<name>/`
- **local mirror** = `cwd/<name>/<tag>/` symlinks into `$ROOT`
- **shared project** = `-s` flag; its `$ROOT` dirs persist and get linked into other projects under the same tag
- **non-project dirs** under a tag are automatically linked as shared resources

## install

```bash
curl -fsSL https://raw.githubusercontent.com/resetself/workspace/main/install.sh | sh
```

or build from source:

```bash
cd ~/Projects/workspace
zig build -Doptimize=ReleaseSafe
cp zig-out/bin/wksp ~/.local/bin/
```

## commands

```
wksp                         list all projects
wksp <name>                  register cwd (targets tag)
wksp <name> @tag,...         register with custom tags
wksp <name> -s [@tag,...]    register as shared project
wksp <name> -l               list tags for project
wksp <name> -k [...]         keep existing local dirs
wksp tag                     list all tags
wksp tag <name,...>          create tags, or list projects
wksp tag <name> -d           delete empty tag
wksp clean                   remove all local dirs + empty ROOT dirs
wksp path [<dir>]            show/set root
```

## examples

```bash
% wksp myapp
# → $ROOT/targets/myapp/        (real dir)
# → ./myapp/targets → $ROOT/targets/myapp

% wksp myapp @tools
# → + $ROOT/tools/myapp/
# → ./myapp/tools/self → $ROOT/tools/myapp

% wksp frida -s @tools/frida
# → shared project, no targets/
# → $ROOT/tools/frida/frida/

% wksp test @tools/frida
# → ./test/tools/frida/
#     ├── self   → $ROOT/tools/frida/test
#     └── frida  → $ROOT/tools/frida/frida   (auto-linked shared)

% wksp
 frida  ~/code/frida [shared]
*test   ~/code/test

% wksp test -l
targets
tools/frida

% wksp tag tools/frida
frida
test

% wksp clean
# → removes local dirs + empty ROOT dirs
# → state preserved

% wksp test
# → rebuilds local dirs from state
```

## state

`~/.config/wksp/state.json`:

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

## build

```bash
zig build                          # debug
zig build -Doptimize=ReleaseSafe   # release
```
