#!/bin/bash
#Keqing213
show_menu() {
    echo "1. Add iptables rule (port-based)"
    echo "2. Remove iptables rule (port-based)"
    echo "3. Add subnet drop rule"
    echo "4. Remove subnet drop rule"
    echo "5. Add port drop for specific subnet"
    echo "6. Remove port drop for specific subnet"
    echo "7. Exit"
    echo -n "Enter your choice: "
}
select_interface() {
    echo "Available network interfaces:"
    interfaces=($(ls /sys/class/net))
    for i in "${!interfaces[@]}"; do
        echo "$i) ${interfaces[$i]}"
    done
    echo -n "Enter the number of the interface to use: "
    read interface_index
    if [[ ! $interface_index =~ ^[0-9]+$ ]] || (( interface_index < 0 || interface_index >= ${#interfaces[@]} )); then
        echo "Invalid selection. Please try again."
        select_interface
    else
        interface=${interfaces[$interface_index]}
    fi
}
add_rule() {
    select_interface
    echo "Current iptables rules in PREROUTING chain of mangle table for interface $interface on port $port:"
    iptables -t mangle -L PREROUTING -v -n --line-numbers
    echo -n "Enter the port number to block: "
    read port
    if [[ ! $port =~ ^[0-9]+$ ]]; then
        echo "Invalid port number. Please enter a valid number."
        return
    fi
    echo "Adding iptables rule for interface $interface on port $port..."
    iptables -t mangle -A PREROUTING -i "$interface" -p tcp --dport "$port" -j DROP
    echo "Rule added."
    exit
}
remove_rule() {
    select_interface
    echo -n "Enter the port number of the rule to delete: "
    read port
    if [[ ! $port =~ ^[0-9]+$ ]]; then
        echo "Invalid port number. Please enter a valid number."
        return
    fi
    echo "Current iptables rules in PREROUTING chain of mangle table for interface $interface on port $port:"
    iptables -t mangle -L PREROUTING -v -n --line-numbers | grep "$interface" | grep "dpt:$port"
    echo -n "Enter the line number of the rule to delete: "
    read line_number
    if [[ $line_number =~ ^[0-9]+$ ]]; then
        iptables -t mangle -D PREROUTING "$line_number"
        echo "Rule deleted."
        exit
    else
        echo "Invalid input. Please enter a number."
        exit
    fi
}

add_subnet_drop() {
    select_interface
    echo -n "Enter the subnet to block (e.g., 192.168.1.0/24): "
    read subnet
    
    # Basic validation for subnet format
    if [[ ! $subnet =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Invalid subnet format. Please use format like 192.168.1.0/24"
        return
    fi
    
    echo "Current iptables rules in PREROUTING chain of mangle table for interface $interface:"
    iptables -t mangle -L PREROUTING -v -n --line-numbers | grep "$interface"
    
    echo "Adding iptables rule to drop traffic from subnet $subnet on interface $interface..."
    iptables -t mangle -A PREROUTING -i "$interface" -s "$subnet" -j DROP
    echo "Subnet drop rule added for $subnet on interface $interface."
    exit
}

remove_subnet_drop() {
    select_interface
    echo -n "Enter the subnet of the rule to delete (e.g., 192.168.1.0/24): "
    read subnet
    
    if [[ ! $subnet =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Invalid subnet format. Please use format like 192.168.1.0/24"
        return
    fi
    
    echo "Current iptables rules in PREROUTING chain of mangle table for interface $interface with subnet $subnet:"
    iptables -t mangle -L PREROUTING -v -n --line-numbers | grep "$interface" | grep "$subnet"
    
    echo -n "Enter the line number of the rule to delete: "
    read line_number
    
    if [[ $line_number =~ ^[0-9]+$ ]]; then
        iptables -t mangle -D PREROUTING "$line_number"
        echo "Subnet drop rule deleted for $subnet."
        exit
    else
        echo "Invalid input. Please enter a number."
        exit
    fi
}

add_subnet_port_drop() {
    select_interface
    echo -n "Enter the subnet to block (e.g., 192.168.1.0/24): "
    read subnet
    
    # Basic validation for subnet format
    if [[ ! $subnet =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Invalid subnet format. Please use format like 192.168.1.0/24"
        return
    fi
    
    echo -n "Enter the port number to block for this subnet: "
    read port
    if [[ ! $port =~ ^[0-9]+$ ]]; then
        echo "Invalid port number. Please enter a valid number."
        return
    fi
    
    echo "Current iptables rules in PREROUTING chain of mangle table for interface $interface:"
    iptables -t mangle -L PREROUTING -v -n --line-numbers | grep "$interface"
    
    echo "Adding iptables rule to drop port $port traffic from subnet $subnet on interface $interface..."
    iptables -t mangle -A PREROUTING -i "$interface" -s "$subnet" -p tcp --dport "$port" -j DROP
    echo "Port drop rule added: port $port blocked for subnet $subnet on interface $interface."
    exit
}

remove_subnet_port_drop() {
    select_interface
    echo -n "Enter the subnet of the rule to delete (e.g., 192.168.1.0/24): "
    read subnet
    
    if [[ ! $subnet =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Invalid subnet format. Please use format like 192.168.1.0/24"
        return
    fi
    
    echo -n "Enter the port number of the rule to delete: "
    read port
    if [[ ! $port =~ ^[0-9]+$ ]]; then
        echo "Invalid port number. Please enter a valid number."
        return
    fi
    
    echo "Current iptables rules in PREROUTING chain of mangle table for interface $interface with subnet $subnet and port $port:"
    iptables -t mangle -L PREROUTING -v -n --line-numbers | grep "$interface" | grep "$subnet" | grep "dpt:$port"
    
    echo -n "Enter the line number of the rule to delete: "
    read line_number
    
    if [[ $line_number =~ ^[0-9]+$ ]]; then
        iptables -t mangle -D PREROUTING "$line_number"
        echo "Subnet port drop rule deleted: port $port for subnet $subnet."
        exit
    else
        echo "Invalid input. Please enter a number."
        exit
    fi
}
while true; do
    show_menu
    read choice
    case $choice in
        1)
            add_rule
            ;;
        2)
            remove_rule
            ;;
        3)
            add_subnet_drop
            ;;
        4)
            remove_subnet_drop
            ;;
        5)
            add_subnet_port_drop
            ;;
        6)
            remove_subnet_port_drop
            ;;
        7)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter 1, 2, 3, 4, 5, 6, or 7."
            ;;
    esac
done
