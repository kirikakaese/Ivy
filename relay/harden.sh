#!/usr/bin/env bash
# Copyright 2026 kiri
# SPDX-License-Identifier: AGPL-3.0-only
#
# One-time hardening of a fresh Debian or Ubuntu server for the Ivy Push
# relay (docs/PUSH_RELAY.md). Safe to run again. Run as root:
#
#   bash harden.sh
#
# - installs security updates now and automatically from then on
# - firewall: only SSH, HTTP and HTTPS come in
# - SSH: keys only, no passwords (skipped while no SSH key is set up, so you
#   can't lock yourself out)
# - fail2ban: blocks addresses that keep failing to log in over SSH
# - kernel network settings against spoofing and SYN floods

set -euo pipefail

say() { printf '\n==> %s\n' "$*"; }
warn() { printf '\n!!  %s\n' "$*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root (for example: sudo bash harden.sh)." >&2
  exit 1
fi
if ! command -v apt-get >/dev/null; then
  echo "This script supports Debian and Ubuntu only." >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive

say "Installing updates and security tools"
apt-get update -q
apt-get upgrade -y -q
apt-get install -y -q ufw fail2ban unattended-upgrades

say "Turning on automatic security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
CONF
cat > /etc/apt/apt.conf.d/52ivy-unattended-upgrades <<'CONF'
// Restart into a new kernel at night when an update needs it.
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
CONF
systemctl enable --now unattended-upgrades >/dev/null

ssh_port="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')"
ssh_port="${ssh_port:-22}"

say "Firewall: SSH (port $ssh_port), HTTP and HTTPS only"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
# limit: allows SSH but blocks addresses that open 6+ connections in 30 s.
ufw limit "$ssh_port/tcp" comment 'SSH' >/dev/null
ufw allow 80/tcp comment 'HTTP (certificates, redirect)' >/dev/null
ufw allow 443/tcp comment 'HTTPS' >/dev/null
ufw --force enable >/dev/null
ufw status verbose | sed -n '1,20p'

say "SSH: keys only"
has_key=false
for keys in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
  if [ -s "$keys" ] && grep -qE '^(ssh-|ecdsa-|sk-)' "$keys"; then
    has_key=true
  fi
done
if $has_key; then
  mkdir -p /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/10-ivy-hardening.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
CONF
  if sshd -t; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd
    echo "Password logins are off. Log in with your SSH key from now on."
  else
    rm -f /etc/ssh/sshd_config.d/10-ivy-hardening.conf
    warn "The SSH settings didn't validate, so SSH is unchanged."
  fi
else
  warn "No SSH key is set up, so password logins stay on. Add your key (ssh-copy-id root@<server>) and run this script again."
fi

say "fail2ban for SSH"
cat > /etc/fail2ban/jail.d/ivy.local <<CONF
[sshd]
enabled = true
port = $ssh_port
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
CONF
systemctl enable --now fail2ban >/dev/null
systemctl restart fail2ban

say "Kernel network settings"
cat > /etc/sysctl.d/90-ivy-hardening.conf <<'CONF'
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
CONF
sysctl --system >/dev/null

say "Done"
echo "Docker publishes only ports 80 and 443 for the relay; everything else stays closed."
if [ -f /var/run/reboot-required ]; then
  echo "An update needs a restart: run 'reboot' when convenient (the relay starts again by itself)."
fi
