# clash-proxy-vless-setup

This repository splits the workflow into two endpoints:

- VPS side: install `Xray VLESS + REALITY` and publish a Clash/Mihomo subscription over HTTPS
- Personal computer side: import the subscription into Clash Verge, Mihomo, or another Clash-compatible client

## What You Get After Installation

After the VPS install finishes successfully, it returns a subscription URL like:

```text
https://<public-ip>.sslip.io:8443/<token>.yaml
```

That subscription file already includes:

- the `vless` proxy node
- `proxy-groups`
- `rules`

So on the personal computer, importing the subscription is normally enough to get both the node and the routing rules.

## Repository Structure

- `server/install-centos.sh`: VPS installer for CentOS / RHEL / Rocky / AlmaLinux / Fedora family
- `server/install-ubuntu.sh`: VPS installer for Ubuntu / Debian-like family
- `server/install.sh`: convenience dispatcher that auto-selects one of the above
- `server/scripts/install-common.sh`: shared install logic
- `server/scripts/open-firewall-centos.sh`: firewall-open script for CentOS / RHEL-like systems
- `server/scripts/open-firewall-ubuntu.sh`: firewall-open script for Ubuntu / Debian-like systems
- `server/config/setup.conf.example`: copy this to `server/config/setup.conf` and edit it
- `server/uninstall-centos.sh`: CentOS / RHEL-like uninstall entrypoint
- `server/uninstall-ubuntu.sh`: Ubuntu / Debian-like uninstall entrypoint
- `server/uninstall.sh`: uninstall dispatcher that auto-selects one of the above
- `client/`: local Clash/Mihomo example files and helpers
- `client/validate-subscription.sh`: validates that a generated Clash profile still contains the expected node and rules

## 1. VPS Installation From Scratch

### Step 1: Prepare the repository on the VPS

Clone or copy this repository onto the VPS, then enter the project directory.

### Step 2: Detect the VPS OS first

Run:

```bash
cat /etc/os-release
```

Choose the installer by the result:

- Ubuntu or Debian-like: `sudo bash server/install-ubuntu.sh`
- CentOS / RHEL / Rocky / AlmaLinux / Fedora-like: `sudo bash server/install-centos.sh`

You can also run `sudo bash server/install.sh`, but the recommended workflow is to identify the OS first and run the matching script explicitly.

### Step 3: Create the private VPS config

Start from the template:

```bash
cp server/config/setup.conf.example server/config/setup.conf
```

Then edit:

```bash
vi server/config/setup.conf
```

Important values:

- `XRAY_PORT`
- `PUBLIC_IP`
- `REALITY_SERVER_NAME`
- `REALITY_DEST`
- `REALITY_FINGERPRINT`
- `SUBSCRIPTION_PORT`
- `XRAY_UUID`
- `REALITY_PRIVATE_KEY`
- `REALITY_PUBLIC_KEY`
- `REALITY_SHORT_ID`
- `SUB_TOKEN`
- `CLASH_PROXY_NAME`
- `CLASH_MIXED_PORT`
- `CLASH_GLOBAL_MODE`
- `CLASH_RULE_MODE`

Use `AUTO_GENERATE` for UUID, REALITY keys, short ID, and subscription token when you want the installer to create them automatically. After install, the final effective values are written back into `server/config/setup.conf`, so you can reuse them directly later.

### Step 4: Run the matching installer

Ubuntu / Debian-like:

```bash
sudo bash server/install-ubuntu.sh
```

CentOS / RHEL-like:

```bash
sudo bash server/install-centos.sh
```

What the installer does:

1. Installs prerequisites.
2. Installs Xray.
3. Generates runtime values when set to `AUTO_GENERATE`.
4. Stops and disables legacy `ss-server@server` if it exists.
5. Writes `/usr/local/etc/xray/config.json`.
6. Installs and configures Caddy.
7. Publishes a Clash/Mihomo subscription YAML over HTTPS.
8. Runs the matching firewall-open script to open SSH, HTTP, Xray, and the subscription port.
9. Handles SELinux port labeling on CentOS-family systems.
10. Regenerates the local example files under `client/active-config/`.
11. Writes the final effective values back into `server/config/setup.conf`.
12. Prints the subscription URL at the end.

### Step 5: Save the subscription URL

The last section of installer output includes:

- server address
- UUID
- REALITY public key
- short ID
- subscription URL

Save the subscription URL. You will use it on the personal computer side.

## 2. Import the Subscription on the Personal Computer

### Clash Verge / Mihomo

1. Open Clash Verge or Mihomo.
2. Add a new subscription profile.
3. Paste the subscription URL returned by the VPS installer.
4. Update or fetch the profile.
5. Select the imported profile and enable it.

Because the subscription YAML already includes `proxies`, `proxy-groups`, and `rules`, the imported profile should directly install the routing rules onto the personal computer client profile.

## 3. Public Templates And Validation

The YAML files under `client/active-config/` are public example templates for this repository. They are not meant to store a user's real local Clash configuration.

Use them for:

- understanding the expected proxy and rule structure
- manual fallback when subscription import fails
- adapting the config to your own environment outside this public repository

To verify the generated example profile structure, run:

```bash
bash client/render-client-configs.sh
bash client/validate-subscription.sh
```

The validator checks that the generated example profile contains:

- a `vless` node
- `proxy-groups`
- `rules`
- REALITY options
- the OpenAI proxy rules
- the Microsoft direct rules

This confirms the example profile structure can carry the rule set required by the personal computer side.

## 4. Manual Fallback And Local Client Notes

If subscription import fails, use one of these example files as a starting point on the personal computer:

- `client/active-config/clash-verge.yaml`
- `client/active-config/clash-verge-check.yaml`
- `client/active-config/custom-routing-rules.yaml`

Clash Verge can usually use them like this:

1. Create a new local profile.
2. Paste the contents of one of the example YAML files.
3. Save and select that profile.

Rule intent in these examples:

- keep Microsoft / Outlook / Office related traffic on `DIRECT`
- send OpenAI related traffic to `PROXY`
- send the rest to `PROXY`
- keep the server IP itself on `DIRECT` to avoid proxy loops

About system proxy settings:

- subscription content can carry proxy nodes, groups, DNS, and `rules:`
- Clash Verge app-level switches such as `Set as system proxy`, TUN mode, or some local UI preferences are still local client settings
- if an app ignores system proxy, use app-specific env vars or wrappers like `client/active-config/opencode-proxy.cmd`

If you want to regenerate the public example files after changing `server/config/setup.conf`, run:

```bash
bash client/render-client-configs.sh
```

The server-side installer also writes generated UUID, REALITY keys, short ID, token, and detected public IP back into `server/config/setup.conf`, so you can regenerate examples from the saved effective values later.

## 5. Migration Notes

This project is designed to migrate a VPS from legacy Shadowsocks to self-hosted `Xray VLESS + REALITY`.

During install it:

- stops and disables `ss-server@server` if it exists
- keeps `/etc/shadowsocks-libev/server.json` in place
- removes old Shadowsocks firewall rules when the old port can be detected

## 6. Security Notes

- Do not commit `server/config/setup.conf`.
- Do not commit real UUIDs, REALITY private keys, public keys, short IDs, private IPs, or subscription URLs.
- Treat `server/config/setup.conf` as machine-specific private data.
- Treat `client/active-config/*.yaml` as public example templates only. Do not turn them into your real long-term local config inside this public repository.



## 7. Uninstall

Use the matching uninstall script on the VPS:

- Ubuntu or Debian-like: `sudo bash server/uninstall-ubuntu.sh`
- CentOS / RHEL-like: `sudo bash server/uninstall-centos.sh`
- Or use the dispatcher: `sudo bash server/uninstall.sh`

The uninstall flow removes Xray, Caddy, subscription files, and the distro-appropriate firewall rules. Legacy Shadowsocks config is still left in place.

