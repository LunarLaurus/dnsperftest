#!/usr/bin/env bash

# Ensure required commands are available
for cmd in bc drill dig; do
    command -v $cmd >/dev/null || {
        echo "error: $cmd was not found. Please install it."
        exit 1
    }
done

# Use drill if available, otherwise use dig
dig_cmd=$(command -v drill || command -v dig)

# Get the nameservers from /etc/resolv.conf
NAMESERVERS=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | sed 's/\(.*\)/&#&/')

# DNS Providers for IPv4 and IPv6
PROVIDERSV4="
1.1.1.1#cloudflare
4.2.2.1#level3
8.8.8.8#google
9.9.9.9#quad9
80.80.80.80#freenom
208.67.222.123#opendns
199.85.126.20#norton
185.228.168.168#cleanbrowsing
77.88.8.7#yandex
176.103.130.132#adguard
156.154.70.3#neustar
8.26.56.26#comodo
45.90.28.202#nextdns
"

PROVIDERSV6="
2606:4700:4700::1111#cloudflare-v6
2001:4860:4860::8888#google-v6
2620:fe::fe#quad9-v6
2620:119:35::35#opendns-v6
2a0d:2a00:1::1#cleanbrowsing-v6
2a02:6b8::feed:0ff#yandex-v6
2a00:5a60::ad1:0ff#adguard-v6
2610:a1:1018::3#neustar-v6
"

# Check for IPv6 support
hasipv6=$($dig_cmd +short +tries=1 +time=2 +stats @2a0d:2a00:1::1 www.google.com | grep -q 216.239.38.120 && echo true)

# Determine providers to test based on argument
case "$1" in
ipv6)
    [ -z "$hasipv6" ] && {
        echo "error: IPv6 support not found. Unable to do the IPv6 test."
        exit 1
    }
    providerstotest=$PROVIDERSV6
    ;;
ipv4)
    providerstotest=$PROVIDERSV4
    ;;
all)
    providerstotest="$PROVIDERSV4"
    [ -n "$hasipv6" ] && providerstotest="$providerstotest $PROVIDERSV6"
    ;;
*)
    providerstotest=$PROVIDERSV4
    ;;
esac

# Accept custom domains from file or command line argument
if [ -f "$2" ]; then
    DOMAINS2TEST=$(cat "$2")
elif [ -n "$2" ]; then
    DOMAINS2TEST="$2"
else
    DOMAINS2TEST="www.google.com amazon.com facebook.com www.youtube.com www.reddit.com wikipedia.org twitter.com gmail.com www.google.com whatsapp.com"
fi

# Logging setup
LOGFILE="dns_test_results.log"
echo "DNS Performance Test Results - $(date)" > "$LOGFILE"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Display header
printf "%-21s" ""
for ((i = 1; i <= $(wc -w <<<"$DOMAINS2TEST"); i++)); do
    printf "test%-8s" "$i"
done
echo "Average"

# Test each provider
for p in $NAMESERVERS $providerstotest; do
    pip="${p%%#*}"
    pname="${p##*#}"
    total_time=0

    printf "%-21s" "$pname"
    for d in $DOMAINS2TEST; do
        ttime="$("$dig_cmd" +tries=1 +time=2 +stats @"$pip" "$d" | awk '/Query time:/ {print $4}')"

        ttime="${ttime:-1000}" # Default to 1000ms if query fails or times out

        if [ "$ttime" -gt 500 ]; then
            printf "${RED}%-8sms${NC}" "$ttime"
        elif [ "$ttime" -gt 100 ]; then
            printf "${YELLOW}%-8sms${NC}" "$ttime"
        else
            printf "${GREEN}%-8sms${NC}" "$ttime"
        fi

        total_time=$((total_time + ttime))
    done

    avg=$(echo "scale=2; $total_time/$(wc -w <<<"$DOMAINS2TEST")" | bc)
    echo "  $avg"

    # Log results
    echo "$pname: $avg ms average response time" >> "$LOGFILE"
done

# Summary of fastest and slowest providers
echo -e "\nFastest Providers:" | tee -a "$LOGFILE"
grep -Eo '[0-9]+\.[0-9]+ ms average response time' "$LOGFILE" | sort -n | head -3 | tee -a "$LOGFILE"

echo -e "\nSlowest Providers:" | tee -a "$LOGFILE"
grep -Eo '[0-9]+\.[0-9]+ ms average response time' "$LOGFILE" | sort -n | tail -3 | tee -a "$LOGFILE"

exit 0