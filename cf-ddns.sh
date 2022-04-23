#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

# Automatically update / create your CloudFlare DNS record to the IP, Dynamic DNS

# Place at:
# curl https://raw.githubusercontent.com/Simcaa/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh > /usr/local/bin/cf-ddns.sh && chmod +x /usr/local/bin/cf-ddns.sh
# run `crontab -e` and add next line:
# */1 * * * * /usr/local/bin/cf-ddns.sh >/dev/null 2>&1
# or you need log:
# */1 * * * * /usr/local/bin/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1


# Usage:
# cf-ddns.sh -k cloudflare-api-key \
#            -u user@example.com \
#            -h "host.example.com" "host.example.com" \   # fqdn of the record you want to update
#            -z example.com \                             # will show you all zones if forgot, but you need this
#            -t A|AAAA \                                  # specify ipv4/ipv6, default: ipv4
#            -m update|create \                           # create new A|AAAA record or update
#            -p false|true                                # cloudflare Proxy Active

# default config

# API key, see https://www.cloudflare.com/a/account/my-account,
# incorrect api-key results in E_UNAUTH error
myCFKEY=
# Username, eg: user@example.com
myCFUSER=
# Zone name, eg: example.com
myCFZONE_NAME=
# Hostname to update, eg: ("homeserver.example.com" "example.com" "home.example.com")
myCFRECORD_NAMES=
# Record type, A(IPv4)|AAAA(IPv6), default IPv4
myCFRECORD_TYPE=A
# update|create
myCFMODE=update
# create|update
myCFPROXY=false
# Cloudflare TTL for record, between 120 and 86400 seconds
myCFTTL=120
# Site to retrieve WAN ip, other examples are: bot.whatismyipaddress.com, https://api.ipify.org/ ...
myWANIPSITE="http://ipv4.icanhazip.com"

# Get current WAN ip
if [ "$myCFRECORD_TYPE" = "A" ]; then
  :
elif [ "$myCFRECORD_TYPE" = "AAAA" ]; then
  myWANIPSITE="http://ipv6.icanhazip.com"
else
  echo "$myCFRECORD_TYPE specified is invalid, CFRECORD_TYPE can only be A(for IPv4)|AAAA(for IPv6)"
  exit 2
fi
myWAN_IP=`curl -s ${myWANIPSITE}`

# get parameter
while getopts k:u:h:z:t:m:p: opts; do
  case ${opts} in
    k) myCFKEY=${OPTARG} ;;
    u) myCFUSER=${OPTARG} ;;
    h) myCFRECORD_NAMES=${OPTARG} ;;
    z) myCFZONE_NAME=${OPTARG} ;;
    t) myCFRECORD_TYPE=${OPTARG} ;;
    m) myCFMODE=${OPTARG} ;;
    p) myCFPROXY=${OPTARG} ;;
  esac
done

# If required settings are missing just exit
if [ "$myCFKEY" = "" ]; then
  echo "Missing api-key, get at: https://www.cloudflare.com/a/account/my-account"
  echo "and save in ${0} or using the -k flag"
  exit 2
fi
if [ "$myCFUSER" = "" ]; then
  echo "Missing username, probably your email-address"
  echo "and save in ${0} or using the -u flag"
  exit 2
fi
# Processing the Hostname Array
for myHOST in ${myCFRECORD_NAMES[@]}; do
  if [ "$myHOST" = "" ]; then
    echo "Missing hostname, what host do you want to update?"
    echo "save in ${0} or using the -h flag"
    exit 2
  fi

  # If the Hostname is not a FQDN
  if [ "$myHOST" != "$myCFZONE_NAME" ] && ! [ -z "${myHOST##*$myCFZONE_NAME}" ]; then
    myHOST="$myHOST.$myCFZONE_NAME"
    echo " => Hostname is not a FQDN, assuming $myHOST"
  fi

	# Get Zone ID from File or API
  if [ ! -d "$HOME/.cf-ddns/" ]; then
    mkdir -p $HOME/.cf-ddns/
  fi
  ID_FILE=$HOME/.cf-ddns/.cf-id_$myCFZONE_NAME.txt
  if [ -f $ID_FILE ] && [ $(wc -l $ID_FILE | cut -d " " -f 1) == 2 ] && [ "$(sed -n '1,1p' "$ID_FILE")" == "$myCFZONE_NAME" ]; then
    myCFZONE_ID=$(sed -n '2,1p' "$ID_FILE")
  else
    echo "Updating Zone ID"
    echo "$myCFZONE_NAME" > $ID_FILE
    myCFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$myCFZONE_NAME" -H "X-Auth-Email: $myCFUSER" -H "X-Auth-Key: $myCFKEY" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
    echo "$myCFZONE_ID" >> $ID_FILE

	  # When updating DNS Record get Record ID
    if [ "$myCFMODE" = "update" ] && [ "$myCFMODE" != "create" ]; then
      myCFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$myCFZONE_ID/dns_records?name=$myHOST" -H "X-Auth-Email: $myCFUSER" -H "X-Auth-Key: $myCFKEY" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
    fi
  fi
  # update cloudflare DNS, trying to update DNS if entry exists
  echo "Processing $myHOST"
  if [ "$myCFMODE" = "update" ] && [ "$myCFMODE" != "create" ]; then

    # update record
    echo "Updating DNS $myCFRECORD_TYPE Record : $myHOST with $myWAN_IP"
    myRESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$myCFZONE_ID/dns_records/$myCFRECORD_ID" \
      -H "X-Auth-Email: $myCFUSER" \
      -H "X-Auth-Key: $myCFKEY" \
      -H "Content-Type: application/json" \
      --data "{\"id\":\"$myCFZONE_ID\",\"type\":\"$myCFRECORD_TYPE\",\"name\":\"$myHOST\",\"content\":\"$myWAN_IP\", \"ttl\":$myCFTTL}")
    else

    # create new record
    echo "Creating DNS $myCFRECORD_TYPE Record : $myHOST with $myWAN_IP"
    myRESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$myCFZONE_ID/dns_records/" \
      -H "X-Auth-Email: $myCFUSER" \
      -H "X-Auth-Key: $myCFKEY" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"$myCFRECORD_TYPE\",\"name\":\"$myHOST\",\"content\":\"$myWAN_IP\", \"ttl\":$myCFTTL}")
    fi

  # check for success
  if [ "$myRESPONSE" != "${myRESPONSE%success*}" ] && [ "$(echo $myRESPONSE | grep "\"success\":true")" != "" ]; then
    echo "Updated succesfuly with following DATA!"
    echo "{\"id\":\"$myCFZONE_ID\",\"type\":\"$myCFRECORD_TYPE\",\"name\":\"$myHOST\",\"content\":\"$myWAN_IP\", \"ttl\":$myCFTTL}"
  else
    echo 'Something went wrong :('
    echo "Response: $RESPONSE"
  fi
  echo "Processed: $myHOST"
done
