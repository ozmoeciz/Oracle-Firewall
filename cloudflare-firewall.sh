#!/usr/bin/env bash
set -euo pipefail

ZONE=public    # change to whatever zone your NIC lives in

ensure_ipset(){
  local name="$1" fam="$2"
  if ! firewall-cmd --permanent --get-ipsets | grep -qw "$name"; then
    firewall-cmd --permanent \
      --new-ipset="$name" --type=hash:net --family="$fam"
    echo "Created permanent ipset $name (family=$fam)"
  else
    echo "Permanent ipset $name already exists"
  fi
}

# 1) Make sure firewalld is up
systemctl is-active --quiet firewalld || systemctl start firewalld

# 2) Create (if needed) the ip-sets
ensure_ipset cloudflare_v4 ipv4
ensure_ipset cloudflare_v6 ipv6
ensure_ipset Home_Network ipv4

# 3) Flush the **permanent** entries
for s in cloudflare_v4 cloudflare_v6 Home_Network; do
  firewall-cmd --permanent --ipset="$s" --flush-entries
done

# 4) Populate Cloudflare lists
for cf in $(curl -s https://www.cloudflare.com/ips-v4); do
  firewall-cmd --permanent --ipset=cloudflare_v4 --add-entry="$cf"
done
for cf in $(curl -s https://www.cloudflare.com/ips-v6); do
  firewall-cmd --permanent --ipset=cloudflare_v6 --add-entry="$cf"
done

# 5) Add your home network
firewall-cmd --permanent --ipset=Home_Network --add-entry=192.168.0.0/23

# 6) Attach rich-rules to the right zone
firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule='rule family="ipv4" source ipset="cloudflare_v4" accept'
firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule='rule family="ipv6" source ipset="cloudflare_v6" accept'
firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule='rule family="ipv4" source ipset="Home_Network" accept'

# 7) Reload to make it live
firewall-cmd --reload
echo "Firewall updated in zone '$ZONE'"
