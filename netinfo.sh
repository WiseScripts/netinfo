#!/bin/bash

dev=
mac=
ip=
gw=
net=
prefix=

ip_to_int() {
  IFS=. read -r i j k l <<< "$1"
  printf "%d" $(((i << 24) + (j << 16) + (k << 8) + l))
}

int_to_ip() {
  printf "%d.%d.%d.%d" \
    $((($1 >> 24) % 256)) $((($1 >> 16) % 256)) $((($1 >> 8) % 256)) $(($1 % 256))
}

get_prefix_from_fib() {
  _IFS=${IFS}
  IFS=$'\n'
  mapfile -t fib < <(cat /proc/net/fib_trie)
  IFS=${_IFS}
  for ((((idx = ${#fib[@]} - 1)); idx >= 0; )); do
    line="${fib[idx]}"
    if [[ ! ${line##*"/32 host LOCAL"*} ]]; then
      ((idx--))
      read -ra fields <<< "${fib[idx]}"
      if [ "${fields[1]}" = "${ip}" ]; then
        break
      fi
    fi
    ((idx--))
  done
  echo "${line}"
  for (( ; idx >= 0; )); do
    line="${fib[idx]}"
    if [[ ! ${line##*"/0"*} ]]; then
      break
    elif [[ ! ${line##*"+--"*} ]]; then
      last_line=${line}
    fi
    ((idx--))
  done
  read -r prefix <<< "$(grep -Po '(?<=/)(\d)+' <<< "${last_line}")"
}

get_net_info() {
  read -ra route <<< "$(ip -o r get 8.8.8.8)"
  if [ "${route[1]}" = "via" ]; then
    gw="${route[2]}"
    dev="${route[4]}"
    ip="${route[6]}"
  else
    gw="openvz"
    dev="${route[2]}"
    ip="${route[4]}"
  fi
  read -ra link <<< "$(ip -o l | grep "${dev}")"
  read -r mac <<< "$(grep -Po '..:..:..:..:..:..' <<< "${link[@]}")"
  read -ra address <<< "$(ip -o -4 a | grep "${ip}")"
  IFS="/" read -r dummy prefix <<< "${address[3]}"
  if [ "$prefix" = 32 ] || [ -z "$prefix" ]; then
    get_prefix_from_fib
  fi
  v=$((0xffffffff ^ ((1 << (32 - prefix)) - 1)))
  msk="$(((v >> 24) & 0xff)).$(((v >> 16) & 0xff)).$(((v >> 8) & 0xff)).$((v & 0xff))"
  msk_int=$(ip_to_int "$msk")
  ip_int=$(ip_to_int "$ip")
  net_int=$((msk_int & ip_int))
  net=$(int_to_ip "$net_int")
  echo "============================================================================================"
  echo "Use <./netinfo.sh test> to test the following information"
  echo "============================================================================================"
  echo "Interface: $dev"
  echo "      MAC: $mac"
  echo "  IP Addr: $ip"
  echo " Net Mask: $msk"
  echo "  Gateway: $gw"
  echo "     CIDR: $ip/$prefix"
  echo "   Subnet: $net/$prefix"
  echo "============================================================================================"
  echo
  echo "wget --no-check-certificate https://moeclub.org/attachment/LinuxShell/InstallNET.sh"
  echo
  echo "--ip-addr $ip --ip-gate $gw --ip-mask $msk"
  echo
  echo "wget --no-check-certificate https://raw.githubusercontent.com/bohanyang/debi/master/debi.sh"
  echo
  echo "--ip $ip --gateway $gw --netmask $msk"
  echo
}

test_net_info() {
  echo "Start test ..."
  echo
  shutdown -r +1 &
  ip a del "$ip" dev "$dev" /dev/null 2>&1
  ip r flush table main
  ip r flush cache
  ip a add "$ip/$prefix" dev "$dev"
  ip a flush "$ip/$prefix" dev "$dev"
  ip r add "$net/$prefix" dev "$dev" scope link src "$ip"
  ip r add default via "$gw" dev "$dev" src "$ip"
  if ping -c 1 -w 10 -q 8.8.8.8 > /dev/null 2>&1; then
    shutdown -c
    echo
    echo "Test OK."
  else
    echo
    echo "Test failed."
    echo "Reboot ..."
  fi
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root." >&2
  exit 1
fi

main() {
  get_net_info

  if [ $# -gt 0 ]; then
    echo
    echo "If the test fails, the machine may need to be restarted!"
    echo
    echo "Press Ctrl+C to cancel. Other key to test ..."
    read -r key
    trap "" INT
    test_net_info
  fi
}

main "$@"
