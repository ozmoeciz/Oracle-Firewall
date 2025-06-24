#!/usr/bin/env bash
set -euo pipefail

ZONE=public
HOME_NET=192.168.0.0/23

run() {
  echo "+ $*" >&2
  "$@"
}

# 1) Ensure firewalld is running
if ! run systemctl is-active --quiet firewalld; then
  run systemctl start firewalld
fi

# 2) Delete & recreate each ipset
for NAME in cloudflare_v4 cloudflare_v6 Home_Network; do
  if firewall-cmd --permanent --get-ipsets | grep -qw "$NAME"; then
    run firewall-cmd --permanent --delete-ipset="$NAME"
  fi
  # pick family
  FAM=ipv4
  [[ "$NAME" == *v6 ]] && FAM=ipv6
  run firewall-cmd --permanent \
    --new-ipset="$NAME" --type=hash:net --family="$FAM"
done

# 3) Populate the Cloudflare sets
echo "Populating Cloudflare IPv4…" >&2
for CF in $(curl -s https://www.cloudflare.com/ips-v4); do
  run firewall-cmd --permanent --ipset=cloudflare_v4 --add-entry="$CF"
done

echo "Populating Cloudflare IPv6…" >&2
for CF in $(curl -s https://www.cloudflare.com/ips-v6); do
  run firewall-cmd --permanent --ipset=cloudflare_v6 --add-entry="$CF"
done

# 4) Add your Home Network
echo "Adding Home_Network entry $HOME_NET…" >&2
run firewall-cmd --permanent --ipset=Home_Network --add-entry="$HOME_NET"

# 5) Attach rich-rules to your zone
run firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule='rule family="ipv4" source ipset="cloudflare_v4" accept'
run firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule='rule family="ipv6" source ipset="cloudflare_v6" accept'
run firewall-cmd --permanent --zone="$ZONE" \
  --add-rich-rule="rule family=\"ipv4\" source ipset=\"Home_Network\" accept"

# 6) Reload to apply
run firewall-cmd --reload

echo "Done. Verify with:"
echo "   firewall-cmd --permanent --info-ipset=Home_Network"
echo "   firewall-cmd --get-ipsets && firewall-cmd --info-ipset=Home_Network"
