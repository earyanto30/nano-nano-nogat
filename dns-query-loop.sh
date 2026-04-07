#!/bin/bash

# Exit if no arguments provided
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <dns_name1> <dns_name2> ..."
    exit 1
fi

# Infinite loop to repeatedly query each DNS name
while true; do
    for dns_name in "$@"; do
        echo "Querying $dns_name at $(date)"
        dig +short "$dns_name"
        echo "-----------------------------"
    done
    sleep 5  # Wait before next round
done
