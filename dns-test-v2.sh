#!/usr/bin/env bash

# Ensure required commands are available
for cmd in bc dig; do
    command -v $cmd >/dev/null || {
        echo "error: $cmd was not found. Please install it."
        exit 1
    }
done

# Use drill if available, otherwise use dig
dig_cmd=$(command -v drill || command -v dig)

# Get the nameservers from /etc/resolv.conf
NAMESERVERS=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | sed 's/\(.*\)/&#&/')

PROVIDERSV4="
1.0.0.1#cloudflare-au
1.1.1.1#cloudflare
1.1.1.2#cloudflare-malware
4.2.2.1#level3
4.4.4.4#yahoo
8.8.8.8#google
8.26.56.26#comodo
9.9.9.9#quad9
9.9.9.10#quad9-alt
45.90.28.202#nextdns
64.6.64.6#dnswatch
64.6.65.6#dnswatch-alt
77.88.8.7#yandex
77.88.8.8#yandex-alt
80.80.80.80#freenom
114.114.114.114#114dns
114.114.115.115#114dns-alt
185.107.232.232#freenom
185.228.168.168#cleanbrowsing
185.228.168.9#cleanbrowsing-alt
199.85.126.20#norton
213.86.33.99#orange
223.5.5.5#aliyun
223.6.6.6#aliyun-alt
41.216.0.9#neotel
196.190.160.1#afrihost
200.106.128.1#globo
181.194.10.1#telesur
156.154.70.3#neustar
156.154.71.3#neustar-alt
"
PROVIDERSV6="
2001:4860:4860::8888#google-v6
2001:500:2f::f#noc
2610:a1:1018::3#neustar-v6
2610:a1:1019::3#neustar-alt-v6
2620:119:35::35#opendns-v6
2620:fe::9#quad9-alt-v6
2620:fe::fe#quad9-v6
2a00:1c40:0:1::2#orange-v6
2a00:5a60::ad1:0ff#adguard-v6
2a0c:fc80:100:6::53#yandex-v6
2a0d:2a00:1::1#cleanbrowsing-v6
2a0d:2a00:1::2#cleanbrowsing-alt-v6
2406:4700:4700::1111#cloudflare-au-v6
240e:3c::1#114dns-v6
240e:3c::2#114dns-alt-v6
2804:14c:0:1::1#globo-v6
2001:42f8:1::1#afrihost-v6
"

# Check for IPv6 support
ipv6_support_check=$($dig_cmd +short AAAA www.google.com)
if [ -n "$ipv6_support_check" ]; then
    hasipv6=true
else
    hasipv6=false
fi

echo "info: DNS Performance check v2"
if [ $hasipv6 != true ]; then
    echo "error: IPv6 support not found. Unable to do the IPv6 tests."
    providerstotest="$PROVIDERSV4"
else
    echo "info: IPv6 support found. Enabling the IPv6 tests."
    providerstotest="$PROVIDERSV4 $PROVIDERSV6"
fi

# Accept custom domains from file or command line argument
if [ -f "$1" ]; then
    DOMAINS2TEST=$(cat "$1")
elif [ -n "$2" ]; then
    DOMAINS2TEST="$1"
else
    DOMAINS2TEST="www.google.com amazon.com facebook.com www.youtube.com www.reddit.com wikipedia.org twitter.com gmail.com www.google.com whatsapp.com"
fi

# Logging setup
LOGFILE="dns_test_results.log"
echo "DNS Performance Test Results - $(date)" >"$LOGFILE"

# Color codes for output
RED='\033[0;31m'
BRIGHT_RED='\033[1;31m'
GREEN='\033[0;32m'
BRIGHT_GREEN='\033[0;92m'
BLUE='\033[0;34m'
BRIGHT_BLUE='\033[0;94m'
YELLOW='\033[0;33m'
BRIGHT_YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Display header
printf "%-21s" ""
num_domains=$(wc -w <<<"$DOMAINS2TEST")

for i in $(seq 1 "$num_domains"); do
    printf "test-%s  " "$i"
done

printf "%-7s" "Average"
echo ""

# Array to store provider results for sorting later
declare -a provider_results

# Test each provider
for p in $NAMESERVERS $providerstotest; do
    pip="${p%%#*}"
    pname="${p##*#}"
    total_time=0

    printf "%-21s" "$pname"
    for d in $DOMAINS2TEST; do
        ttime="$("$dig_cmd" +tries=1 +time=2 +stats @"$pip" "$d" | awk '/Query time:/ {print $4}')"

        ttime="${ttime:-1000}" # Default to 1000ms if query fails or times out

        if [ "$ttime" -gt 999 ]; then
            printf "${RED}%sms${NC}  " "$ttime"
        elif [ "$ttime" -gt 499 ]; then
            printf "${BRIGHT_RED}%sms${NC}   " "$ttime"
        elif [ "$ttime" -gt 299 ]; then
            printf "${YELLOW}%sms${NC}   " "$ttime"
        elif [ "$ttime" -gt 199 ]; then
            printf "${BRIGHT_YELLOW}%sms${NC}   " "$ttime"
        elif [ "$ttime" -gt 99 ]; then
            printf "${GREEN}%sms${NC}   " "$ttime"
        elif [ "$ttime" -gt 49 ]; then
            printf "${BRIGHT_GREEN}%sms${NC}    " "$ttime"
        elif [ "$ttime" -gt 9 ]; then
            printf "${BLUE}%sms${NC}    " "$ttime"
        else
            printf "${BRIGHT_BLUE}%sms${NC}     " "$ttime"
        fi

        total_time=$((total_time + ttime))
    done

    avg=$(echo "scale=2; $total_time/$(wc -w <<<"$DOMAINS2TEST")" | bc)
    printf " %-9s" "${avg}ms"
    echo ""

    # Store the result for sorting later
    provider_results+=("$avg ms - $pname")

    # Log results
    echo "$pname: $avg ms average response time" >>"$LOGFILE"
done

# Sort and display the fastest and slowest providers
mapfile -t sorted < <(printf "%s\n" "${provider_results[@]}" | sort -n)

echo -e "\nFastest Providers:" | tee -a "$LOGFILE"
for i in {0..2}; do
    printf "${GREEN}%s${NC}\n" "${sorted[$i]}" | tee -a "$LOGFILE"
done
echo ""

echo -e "\nSlowest Providers:" | tee -a "$LOGFILE"
for i in $(seq $((${#sorted[@]} - 3)) $((${#sorted[@]} - 1))); do
    printf "${RED}%s${NC}\n" "${sorted[$i]}" | tee -a "$LOGFILE"
done
echo ""

exit 0
