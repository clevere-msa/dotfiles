#!/usr/bin/env bash
    
# OpenSSL requires the port number.
HOST=$1
PORT=$2
DELAY=0.1
ciphers=$(openssl ciphers 'ALL:eNULL' | sed -e 's/:/ /g')
protocols=("ssl3" "tls1" "tls1_1" "tls1_2")
cafile=/etc/pki/tls/certs/usb_chain.pem
    
echo Obtaining cipher list from $(openssl version).
    
for cipher in ${ciphers[@]};
do
  for protocol in ${protocols[@]};
  do
    echo -n Testing $cipher with $protocol...
    result=$(echo -n | openssl s_client -$protocol -cipher "$cipher" -connect $HOST:$PORT -CAfile $cafile 2>&1)
    if [[ "$result" =~ "error" ]] ; then
      error=$(echo -n $result | cut -d':' -f6)
      echo NO \($error\)
    elif [[ "$result" =~ "Cipher is (NONE)" ]] ; then
      echo "NO (No cipher)"
    elif [[ "$result" =~ "Cipher is ${cipher}" || "$result" =~ "Cipher    :" ]] ; then
      echo YES
    else
      echo UNKNOWN RESPONSE
      echo $result
    fi
  done
  
  sleep $DELAY
done


