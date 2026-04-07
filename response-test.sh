#!/bin/bash

url=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --url) url="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$url" ]; then
    echo "Usage: $0 --url <URL>"
    exit 1
fi

while true; do
  response=$(curl -s -w "%{http_code}" $url -o /dev/null)
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")

  if [[ "$response" == 2* || "$response" == 3* || "$response" == 4* ]]; then
    echo -e "\033[0;32m[$timestamp] [$response] OK\033[0m"
  else
    echo -e "\033[0;31m[$timestamp] [$response] NOT OK\033[0m"
  fi

  sleep 1
done
