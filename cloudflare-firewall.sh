#!/usr/bin/env bash
set -euo pipefail

ZONE=public      # adjust to your active zone if different
HOME_NET=192.168.0.0/23

run() { 
  echo "+ $*" >&2
  "$@"
}

# 1) Make sure firewalld is running
if ! run systemctl is-active --quiet firewalld; then
  run systemctl start firewalld
fi

# 2) Remove & recreate each ipset so entries are always fresh
for NAME in cloudflare_v4 cloudflare_v6 Home_Network; do
  if run firewall-cmd --permanent --get-ipsets | grep -qw "$NAME"; then
    run firewall-cmd --permanent --remove-ipset="$NAME"
  fi
  # pick family based on name suffix
  if [[ "$NAME" == *v6 ]]; then FAM=ipv6; else FAM=ipv4; fi
  run firewall-cmd --permanent \
    --new-ipset="$NAME" --type=hash:net --family="$FAM"
done

# 3) Populate the Cloudflare ipsets
echo "Fetching Cloudflare IPv4…" >&2
for CF in $(curl -s https://www.cloudflare.com/ips-v4); do
  run firewall-cmd --permanent --ipset=cloudflare_v4 --add-entry="$CF"
done

echo "Fetching Cloudflare IPv6…" >&2
for CF in $(curl -s https://www.cloudflare.com/ips-v6); do
  run firewall-cmd --permanent --ipset=cloudflare_v6 --add-entry="$CF"
done

# 4) Add your Home Network
echo "Adding Home_Network entry $HOME_NET…" >&2
run firewall-cmd --permanent --ipset=Home_Network --add-entry="$HOME_NET"

# 5) Attach rich-rules in the correct zone
run firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule='rule family="ipv4" source ipset="cloudflare_v4" accept'
run firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule='rule family="ipv6" source ipset="cloudflare_v6" accept'
run firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule="rule family=\"ipv4\" source ipset=\"Home_Network\" accept"

# 6) Finally, reload to push permanent → runtime
run firewall-cmd --reload

echo "✅ Done. Check with: firewall-cmd --permanent --info-ipset=Home_Network" >&2
