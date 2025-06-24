#!/usr/bin/env bash
set -euo pipefail

# 1) Make sure firewalld is running
if ! systemctl is-active --quiet firewalld; then
  echo "Starting firewalld…" >&2
  systemctl start firewalld
fi

# 2) Create IP sets (idempotent)
for set in cloudflare_v4 cloudflare_v6 Home_Network; do
  firewall-cmd --permanent --new-ipset="$set" --type=hash:net \
    || echo "IPSet $set already exists" >&2
done

# 3) Populate Cloudflare IPs
echo "Fetching Cloudflare IPs…" >&2
for cf in $(curl -s https://www.cloudflare.com/ips-v4); do
  firewall-cmd --permanent --ipset=cloudflare_v4 --add-entry="$cf"
done
for cf in $(curl -s https://www.cloudflare.com/ips-v6); do
  firewall-cmd --permanent --ipset=cloudflare_v6 --add-entry="$cf"
done

# 4) Add your home network
echo "Adding Home Network (192.168.0.0/23) to Home_Network set…" >&2
firewall-cmd --permanent --ipset=Home_Network --add-entry=192.168.0.0/23

# 5) Allow all traffic from those sets
for fam in ipv4 ipv6; do
  firewall-cmd --permanent \
    --add-rich-rule="rule family=\"$fam\" source ipset=\"cloudflare_${fam#ip}\" accept"
done

# And home network (IPv4 only)
firewall-cmd --permanent \
  --add-rich-rule='rule family="ipv4" source ipset="Home_Network" accept'

# 6) Reload to apply
echo "Reloading firewalld…" >&2
firewall-cmd --reload

echo "Done – Cloudflare IPs and Home Network are trusted. 🛡️"
