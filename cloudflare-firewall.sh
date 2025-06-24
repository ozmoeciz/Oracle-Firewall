#!/usr/bin/env bash
set -euo pipefail

# helper: only create an ipset if missing
ensure_ipset(){
  local name="$1" fam="$2"
  if ! firewall-cmd --get-ipsets | grep -qw "$name"; then
    firewall-cmd --permanent --new-ipset="$name" --type=hash:net --family="$fam"
    echo "Created ipset $name (family=$fam)"
  else
    echo "ipset $name already exists"
  fi
}

# 1) start firewalld if needed
if ! systemctl is-active --quiet firewalld; then
  systemctl start firewalld
fi

# 2) ensure all three sets
ensure_ipset cloudflare_v4 ipv4
ensure_ipset cloudflare_v6 ipv6
ensure_ipset Home_Network ipv4

# 3) flush them so we start clean
for set in cloudflare_v4 cloudflare_v6 Home_Network; do
  firewall-cmd --permanent --ipset="$set" --flush-entries
done

# 4) populate CF lists
echo "Populating Cloudflare v4…"
for cf in $(curl -s https://www.cloudflare.com/ips-v4); do
  firewall-cmd --permanent --ipset=cloudflare_v4 --add-entry="$cf"
done

echo "Populating Cloudflare v6…"
for cf in $(curl -s https://www.cloudflare.com/ips-v6); do
  firewall-cmd --permanent --ipset=cloudflare_v6 --add-entry="$cf"
done

# 5) add your home network
firewall-cmd --permanent --ipset=Home_Network --add-entry=192.168.0.0/23

# 6) allow traffic from those sets
firewall-cmd --permanent \
  --add-rich-rule='rule family="ipv4" source ipset="cloudflare_v4" accept'
firewall-cmd --permanent \
  --add-rich-rule='rule family="ipv6" source ipset="cloudflare_v6" accept'
firewall-cmd --permanent \
  --add-rich-rule='rule family="ipv4" source ipset="Home_Network" accept'

# 7) reload to apply
firewall-cmd --reload
echo "Firewall updated cleanly."
