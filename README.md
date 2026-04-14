# clash-proxy-vless-setup

在 VPS 上安装 `Xray VLESS + REALITY`，并发布可直接导入 Clash Verge / Mihomo 的订阅。

## 安装

### 1. 在 VPS 上准备仓库

```bash
git clone <your-repo-url>
cd clash-proxy-vless-setup
```

### 2. 先确认 VPS 系统

```bash
cat /etc/os-release
```

- Ubuntu / Debian 类系统：使用 `server/install-ubuntu.sh`
- CentOS / RHEL / Rocky / AlmaLinux / Fedora 类系统：使用 `server/install-centos.sh`

### 3. 创建并编辑配置文件

先复制模板：

```bash
cp server/config/setup.conf.example server/config/setup.conf
```

再编辑：

```bash
vi server/config/setup.conf
```

用户主要需要关注这个文件：`server/config/setup.conf`

常用可自定义项：

- `XRAY_PORT`
- `PUBLIC_IP`
- `REALITY_SERVER_NAME`
- `REALITY_DEST`
- `SUBSCRIPTION_PORT`
- `CLASH_PROXY_NAME`
- `CLASH_DIRECT_EXTRA_DOMAINS`

说明：

- `server/config/setup.conf.example` 只是模板，不直接使用
- `server/config/setup.conf` 是你的本地私有配置文件
- 安装后自动生成的有效值会写回 `server/config/setup.conf`
- `server/config/setup.conf` 不被 Git 追踪

如果学校邮箱、SSO 或学校门户需要走直连，可以在这里追加域名，例如：

```bash
CLASH_DIRECT_EXTRA_DOMAINS=mail.school.edu,login.school.edu,sso.school.edu
```

### 4. 运行安装脚本

Ubuntu / Debian：

```bash
sudo bash server/install-ubuntu.sh
```

CentOS / RHEL / Rocky / AlmaLinux / Fedora：

```bash
sudo bash server/install-centos.sh
```

安装完成后，脚本会输出订阅 URL。

## 使用

在个人电脑上打开 Clash Verge 或 Mihomo：

1. 新建订阅
2. 粘贴安装完成后输出的订阅 URL
3. 更新订阅
4. 选中并启用该配置

默认情况下，订阅已经包含：

- 节点
- `proxy-groups`
- `rules`

导入后即可直接使用。

如果你还想查看本地生成的客户端示例文件，VPS 安装脚本会把它们写到 `client/local-config/`。这个目录不被 Git 跟踪，不会因为安装后生成文件而影响后续 `git pull`。

## 更新

如果你更新了仓库代码，或修改了 `server/config/setup.conf`，在 VPS 上重新运行对应安装脚本即可刷新订阅内容：

```bash
sudo bash server/install-ubuntu.sh
```

或：

```bash
sudo bash server/install-centos.sh
```

仓库里的 `client/active-config/*` 是静态示例模板；VPS 安装后实际生成的本地文件会写到 `client/local-config/*`，避免污染 Git 工作区。

## 卸载

Ubuntu / Debian：

```bash
sudo bash server/uninstall-ubuntu.sh
```

CentOS / RHEL / Rocky / AlmaLinux / Fedora：

```bash
sudo bash server/uninstall-centos.sh
```
