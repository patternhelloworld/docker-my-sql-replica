#!/bin/bash
ssh_test(){
  for i in $(seq 229 255);do
      sshpass -p ssh -q -o ConnectTimeout=3 ${2}@${1}${i} exit
      let ret=$?
      if [ $ret -eq 5 ]; then
          echo $1$i "Refused!"  $ret
      elif [ $ret -eq 255 ] ; then
          echo $1$i "Server Down!" $ret
      elif [ $ret -eq 0 ] ; then
          echo $1$i "Connnected!" $ret
      else
          echo $1$i "Unknown return code!" $ret
      fi
  done
}

ssh_test '10.3.0.10' 'root'