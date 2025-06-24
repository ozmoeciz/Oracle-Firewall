#!/usr/bin/env bash
set -euo pipefail

ZONE=public
HOME_NET=192.168.0.0/23

# Helper: echo the command before running it
run() {
  echo "+ $*" >&2
  "$@"
}

# 1) Ensure firewalld is running
systemctl is-active --quiet firewalld || run systemctl start firewalld

# 2) Delete & recreate cloudflare_v4
if firewall-cmd --permanent --get-ipsets | grep -qw cloudflare_v4; then
  run firewall-cmd --permanent --delete-ipset=cloudflare_v4
fi
run firewall-cmd --permanent --new-ipset=cloudflare_v4 --type=hash:net

# 3) Delete & recreate cloudflare_v6
if firewall-cmd --permanent --get-ipsets | grep -qw cloudflare_v6; then
  run firewall-cmd --permanent --delete-ipset=cloudflare_v6
fi
run firewall-cmd --permanent --new-ipset=cloudflare_v6 --type=hash:net

# 4) **Minimal Home_Network snippet**: delete, recreate, **then** add-entry
if firewall-cmd --permanent --get-ipsets | grep -qw Home_Network; then
  run firewall-cmd --permanent --delete-ipset=Home_Network
fi
run firewall-cmd --permanent --new-ipset=Home_Network --type=hash:net
run firewall-cmd --permanent --ipset=Home_Network --add-entry="$HOME_NET"

# 5) Populate Cloudflare IPv4
echo "Populating Cloudflare v4…" >&2
for CF in $(curl -s https://www.cloudflare.com/ips-v4); do
  run firewall-cmd --permanent --ipset=cloudflare_v4 --add-entry="$CF"
done

# 6) Populate Cloudflare IPv6
echo "Populating Cloudflare v6…" >&2
for CF in $(curl -s https://www.cloudflare.com/ips-v6); do
  run firewall-cmd --permanent --ipset=cloudflare_v6 --add-entry="$CF"
done

# 7) Attach rich-rules to the public zone
run firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule='rule family="ipv4" source ipset="cloudflare_v4" accept'
run firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule='rule family="ipv6" source ipset="cloudflare_v6" accept'
run firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule='rule family="ipv4" source ipset="Home_Network" accept'

# 8) Reload to activate everything
run firewall-cmd --reload

echo "Done! Verify with:"
echo "   firewall-cmd --permanent --info-ipset=Home_Network"
echo "   firewall-cmd --get-ipsets && firewall-cmd --info-ipset=Home_Network"
