#!/usr/bin/env bash
set -euo pipefail

ZONE=public
HOME_NET=192.168.0.0/23

run() {
  echo "+ $*" >&2
  "$@"
}

# 1) Ensure firewalld is running
systemctl is-active --quiet firewalld || run systemctl start firewalld

# 2) Delete & recreate each ipset with the correct family
for NAME in cloudflare_v4 cloudflare_v6 Home_Network; do
  if firewall-cmd --permanent --get-ipsets | grep -qw "$NAME"; then
    run firewall-cmd --permanent --delete-ipset="$NAME"
  fi

  if [[ "$NAME" == *v6 ]]; then
    run firewall-cmd --permanent \
      --new-ipset="$NAME" --type=hash:net --family=ip6
  else
    run firewall-cmd --permanent \
      --new-ipset="$NAME" --type=hash:net --family=ip
  fi
done

# 3) Populate Cloudflare IPv4
echo "Populating Cloudflare IPv4…" >&2
for CF in $(curl -s https://www.cloudflare.com/ips-v4); do
  run firewall-cmd --permanent --ipset=cloudflare_v4 --add-entry="$CF"
done

# 4) Populate Cloudflare IPv6
echo "Populating Cloudflare IPv6…" >&2
for CF in $(curl -s https://www.cloudflare.com/ips-v6); do
  run firewall-cmd --permanent --ipset=cloudflare_v6 --add-entry="$CF"
done

# 5) Add your Home Network (IPv4)
echo "Adding Home_Network entry $HOME_NET…" >&2
run firewall-cmd --permanent --ipset=Home_Network --add-entry="$HOME_NET"

# 6) Attach rich-rules
for RULE in \
  'rule family="ipv4" source ipset="cloudflare_v4" accept' \
  'rule family="ipv6" source ipset="cloudflare_v6" accept' \
  'rule family="ipv4" source ipset="Home_Network" accept"
do
  run firewall-cmd --permanent --zone="$ZONE" --add-rich-rule="$RULE"
done

# 7) Reload to apply
run firewall-cmd --reload

echo "  All done! Verify with:"
echo "  firewall-cmd --permanent --info-ipset=Home_Network"
echo "  firewall-cmd --get-ipsets && firewall-cmd --info-ipset=Home_Network"
