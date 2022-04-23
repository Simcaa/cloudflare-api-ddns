#!/bin/sh
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
#            -h host.example.com \                        # fqdn of the record you want to update
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
# Hostname to update, eg: *.example.com
myCFHOST_NAME=
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
    h) myCFHOST_NAME=${OPTARG} ;;
    z) myCFZONE_NAME=${OPTARG} ;;
    t) myCFRECORD_TYPE=${OPTARG} ;;
    m) myCFMODE=${OPTARG} ;;
    p) myCFPROXY=${OPTARG} ;;
  esac
done

# define logfile
logfile=~/$myCFHOST_NAME.log
date > $logfile
echo "------------------------------" >> $logfile
echo -e "Processing $myCFHOST_NAME\n" >> $logfile

# If required settings are missing just exit
if [ "$myCFKEY" = "" ]; then
  echo "Missing api-key, get at: https://www.cloudflare.com/a/account/my-account" >> $logfile
  echo "and save in ${0} or using the -k flag" >> $logfile
  exit 2
fi
if [ "$myCFUSER" = "" ]; then
  echo "Missing username, probably your email-address" >> $logfile
  echo "and save in ${0} or using the -u flag" >> $logfile
  exit 2
fi
# Processing the Hostname Array
if [ "$myCFHOST_NAME" = "" ]; then
  echo "Missing hostname, what host do you want to update?" >> $logfile
  echo "save in ${0} or using the -h flag" >> $logfile
  exit 2
fi

# If the Hostname is not a FQDN
if [ "$myCFHOST_NAME" != "$myCFZONE_NAME" ] && ! [ -z "${myCFHOST_NAME##*$myCFZONE_NAME}" ]; then
  myCFHOST_NAME="$myCFHOST_NAME.$myCFZONE_NAME"
  echo " => Hostname is not a FQDN, assuming $myCFHOST_NAME" >> $logfile
fi

# Get Zone ID from File or API
echo -e "\nGetting Zone ID" >> $logfile
myCFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$myCFZONE_NAME" -H "X-Auth-Email: $myCFUSER" -H "X-Auth-Key: $myCFKEY" -H "Content-Type: application/json" | jq -r '{"result"}[] | .[0] | .id' )
echo "$myCFZONE_NAME has this ID : " >> $logfile
echo "$myCFZONE_ID" >> $logfile

# When updating DNS Record get Record ID
if [ "$myCFMODE" = "update" ]; then
  echo -e "\nGetting RECORD ID" >> $logfile
  myCFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$myCFZONE_ID/dns_records?name=$myCFHOST_NAME" -H "X-Auth-Email: $myCFUSER" -H "X-Auth-Key: $myCFKEY" -H "Content-Type: application/json" | jq -r '{"result"}[] | .[0] | .id' )
  echo "$myCFHOST_NAME has this ID : " >> $logfile
  echo "$myCFRECORD_ID" >> $logfile
fi

# update cloudflare DNS, trying to update DNS if entry exists
if [ "$myCFMODE" = "update" ]; then

  # update record
  echo -e "\nUpdating DNS $myCFRECORD_TYPE Record : $myCFHOST_NAME with $myWAN_IP" >> $logfile
  myRESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$myCFZONE_ID/dns_records/$myCFRECORD_ID" \
    -H "X-Auth-Email: $myCFUSER" \
    -H "X-Auth-Key: $myCFKEY" \
    -H "Content-Type: application/json" \
    --data "{\"id\":\"$myCFZONE_ID\",\"type\":\"$myCFRECORD_TYPE\",\"name\":\"$myCFHOST_NAME\",\"content\":\"$myWAN_IP\", \"ttl\":$myCFTTL}")
  else

  # create new record
  echo "Creating DNS $myCFRECORD_TYPE Record : $myCFHOST_NAME with $myWAN_IP" >> $logfile
  myRESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$myCFZONE_ID/dns_records/" \
    -H "X-Auth-Email: $myCFUSER" \
    -H "X-Auth-Key: $myCFKEY" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"$myCFRECORD_TYPE\",\"name\":\"$myCFHOST_NAME\",\"content\":\"$myWAN_IP\", \"ttl\":$myCFTTL}")
  fi

# check for success
if [ "$myRESPONSE" != "${myRESPONSE%success*}" ] && [ "$(echo $myRESPONSE | grep "\"success\":true")" != "" ]; then
  echo "Updated succesfuly with following DATA!" >> $logfile
  echo -e "{\"id\":\"$myCFZONE_ID\",\"type\":\"$myCFRECORD_TYPE\",\"name\":\"$myCFHOST_NAME\",\"content\":\"$myWAN_IP\", \"ttl\":$myCFTTL}\n" >> $logfile
else
  echo 'Something went wrong :(' >> $logfile
  echo "Response: $myRESPONSE" >> $logfile
fi
echo ""
echo "Processed: $myCFHOST_NAME" >> $logfile
echo "------------------------------" >> $logfile
date >> $logfile
