#!/usr/bin/env bash
set -euo pipefail

ZONE=public     # adjust if your interface lives in a different zone

# helper: log & run
run() {
  echo "+ $*" >&2
  "$@"
}

# 1) Ensure firewalld is running
if ! run systemctl is-active --quiet firewalld; then
  run systemctl start firewalld
fi

# 2) Create ip-sets if missing
for NAME in cloudflare_v4 cloudflare_v6 Home_Network; do
  if ! run firewall-cmd --permanent --get-ipsets | grep -qw "$NAME"; then
    run firewall-cmd --permanent \
      --new-ipset="$NAME" --type=hash:net \
      --family=$([[ "$NAME" == *v6 ]] && echo ipv6 || echo ipv4)
  else
    echo "– ipset $NAME already exists" >&2
  fi
done

# 3) Flush ALL entries from the permanent sets
for NAME in cloudflare_v4 cloudflare_v6 Home_Network; do
  run firewall-cmd --permanent --ipset="$NAME" --flush-entries
done

# 4) Populate Cloudflare lists (permanent)
echo "Fetching Cloudflare v4…" >&2
for CF in $(curl -s https://www.cloudflare.com/ips-v4); do
  run firewall-cmd --permanent --ipset=cloudflare_v4 --add-entry="$CF"
done

echo "Fetching Cloudflare v6…" >&2
for CF in $(curl -s https://www.cloudflare.com/ips-v6); do
  run firewall-cmd --permanent --ipset=cloudflare_v6 --add-entry="$CF"
done

# 5) **Critical**: add your Home Network entry
echo "Adding Home_Network entry 192.168.0.0/23…" >&2
run firewall-cmd --permanent --ipset=Home_Network --add-entry=192.168.0.0/23

# 6) Attach rich-rules to your chosen zone
for RULE in \
  'rule family="ipv4" source ipset="cloudflare_v4" accept' \
  'rule family="ipv6" source ipset="cloudflare_v6" accept' \
  'rule family="ipv4" source ipset="Home_Network" accept'
do
  run firewall-cmd --permanent --zone="$ZONE" --add-rich-rule="$RULE"
done

# 7) Reload to activate
run firewall-cmd --reload

echo "Done. Permanent ipsets now include your Home_Network entry." >&2
