#!/bin/bash

# Setup logging
# LOG_FILE="/var/log/devopsfetch.log"
LOG_FILE="./devopsfetch.log"

log() {
    local msg="$1"
    local level="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $level - $msg" >> $LOG_FILE
}

usage(){
    echo "Usage: devopsfetch [OPTION]...
Retrieve and display system information.

Options:
  -p, --port [PORT]          Display all active ports and services, or detailed info for a specific port
  -d, --docker [NAME]        List all Docker images and containers, or detailed info for a specific container
  -n, --nginx [DOMAIN]       Display all Nginx domains and their ports, or detailed configuration for a specific domain
  -u, --users [USER]         List all users and their last login times, or detailed info for a specific user
  -t, --time START [END]   Display activities within a specified time range or a single day
  -h, --help                 Display this help and exit
"
}


time_range_is_valid() {
    local start_date="$1"
    local end_date="$2"
    
    if ! date -d "$start_date" &> /dev/null || ! date -d "$end_date" &> /dev/null; then
        echo "Invalid date format"
        return 1
    fi
    
    start_date=$(date -d "$start_date" '+%Y-%m-%d')
    end_date=$(date -d "$end_date" '+%Y-%m-%d')
    now=$(date '+%Y-%m-%d')
    
    if [[ "$start_date" > "$now" || "$end_date" > "$now" ]]; then
        echo "Error: Start and end dates must not be in the future."
        return 1
    elif [[ "$start_date" > "$end_date" ]]; then
        echo "Error: Start date must be before or equal to end date."
        return 1
    fi
    
    return 0
}

get_listening_port() {
    local service_address="$1"
    if [[ "$service_address" == *"->"* ]]; then
        echo "${service_address%%->*}" | cut -d':' -f2
    else
        echo "$service_address" | cut -d':' -f2
    fi
}

list_port() {
    local port="$1"
    local lsof_output
    
    if [ -n "$port" ]; then
        lsof_output=$(lsof -P -n -i ":$port" 2>/dev/null)
        if [ -z "$lsof_output" ]; then
            echo "No open port with number $port found."
            return
        fi
        
        local port_details=$(echo "$lsof_output" | awk 'NR==2')
        local user=$(echo "$port_details" | awk '{print $3}')
        local service=$(echo "$port_details" | awk '{print $1}')
        local port_type=$(echo "$port_details" | awk '{print $8}')
        local pid=$(echo "$port_details" | awk '{print $2}')
        local listening_port=$(get_listening_port "$(echo "$port_details" | awk '{print $9}')")
        
        printf "%-12s %-12s\n" "Field" "Value"
        printf "%-12s %-12s\n" "User" "$user"
        printf "%-12s %-12s\n" "Port" "$listening_port"
        printf "%-12s %-12s\n" "Service" "$service"
        printf "%-12s %-12s\n" "Port Type" "$port_type"
        printf "%-12s %-12s\n" "Process ID" "$pid"
    else
        lsof_output=$(lsof -P -n -i 2>/dev/null)
        if [ -z "$lsof_output" ]; then
            echo "No open ports found."
            return
        fi
        
        printf "%-12s %-12s %-12s\n" "USER" "PORT" "SERVICE"
        echo "$lsof_output" | awk 'NR>1 {split($9, a, ":"); printf "%-12s %-12s %-12s\n", $3, a[2], $1}'
    fi
    
    log "Ports listed." "INFO"
}

list_docker_objects() {
    local container_name="$1"
    
    if [ -n "$container_name" ]; then
        local container_info=$(docker inspect "$container_name" 2>/dev/null)
        if [ -z "$container_info" ]; then
            echo "No information found for container $container_name."
            return
        fi
        
        local container=$(echo "$container_info" | jq '.[0]')
        local id=$(echo "$container" | jq -r '.Id')
        local name=$(echo "$container" | jq -r '.Name')
        local created=$(echo "$container" | jq -r '.Created')
        local path=$(echo "$container" | jq -r '.Path')
        local args=$(echo "$container" | jq -r '.Args')
        local image=$(echo "$container" | jq -r '.Image')
        
        printf "%-15s %-40s\n" "Field" "Value"
        printf "%-15s %-40s\n" "ID" "$id"
        printf "%-15s %-40s\n" "Name" "$name"
        printf "%-15s %-40s\n" "Created At" "$created"
        printf "%-15s %-40s\n" "Path" "$path"
        printf "%-15s %-40s\n" "Args" "$args"
        printf "%-15s %-40s\n" "Image" "$image"
        
        log "Detailed information for container $container_name displayed." "INFO"
    else
        local images=$(docker images --format "{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}" 2>/dev/null)
        local containers=$(docker ps -a --format "{{.ID}}\t{{.Image}}\t{{.Command}}\t{{.CreatedAt}}\t{{.Status}}\t{{.Names}}" 2>/dev/null)
        
        echo "Docker Images"
        printf "%-20s %-10s %-20s %-15s\n" "Repository" "Tag" "ID" "Created Since"
        echo "$images" | awk -F'\t' '{printf "%-20s %-10s %-20s %-15s\n", $1, $2, $3, $4}'
        echo "-----------------------------------------------------------------------------------------------------"
        echo "Docker Containers"
        printf "%-15s %-20s %-30s %-20s %-20s %-20s\n" "ID" "Image" "Command" "Created At" "Status" "Names"
        echo "$containers" | awk -F'\t' '{printf "%-15s %-20s %-30s %-20s %-20s %-20s\n", $1, $2, $3, $4, $5, $6}'
        
        log "Docker images and containers listed." "INFO"
    fi
}

list_nginx() {
    local domain="$1"
    local nginx_conf_dirs=('/etc/nginx/sites-enabled' '/etc/nginx/sites-available' '/etc/nginx/conf.d')
    local table=$(mktemp)
    
    printf "%-20s %-40s %-40s\n" "Domain" "Proxy" "Config File" > "$table"
    
    for conf_dir in "${nginx_conf_dirs[@]}"; do
        # Check if the directory exists
        if [ ! -d "$conf_dir" ]; then
            continue
        fi

        # Check if the directory is empty
        if [ -z "$(ls -A "$conf_dir")" ]; then
            continue
        fi
        for conf_file in "$conf_dir"/*; do
            if [ ! -f "$conf_file" ]; then
                continue
            fi
            local conf_content=$(cat "$conf_file")
            local server_names=$(echo "$conf_content" | grep -Eo 'server_name\s+[^;]+' | awk '{print $2}')
            local proxies=$(echo "$conf_content" | grep -Eo 'proxy_pass\s+http://[^;]+' | awk '{print $2}')
            [ -z "$server_names" ] && server_names="default"
            [ -z "$proxies" ] && proxies="N/A"
            
            for server_name in $server_names; do
                if [ -n "$domain" ] && [[ ! " $server_name " =~ " $domain " ]]; then
                    continue
                fi
                
                for proxy in $proxies; do
                    printf "%-20s %-40s %-40s\n" "$server_name" "$proxy" "$conf_file" >> "$table"
                done
            done
        done
    done
    
    if [ -n "$domain" ] && [ $(wc -l < "$table") -eq 1 ]; then
        echo "No configuration found for domain $domain."
    else
        cat "$table"
    fi
    
    rm "$table"
    log "Nginx domains and proxies listed." "INFO"
}

list_users() {
    local username="$1"
    
    if [ -n "$username" ]; then
        local user_info=$(getent passwd "$username")
        if [ -z "$user_info" ]; then
            echo "No detailed information found for user $username."
            log "No detailed information found for user $username." "INFO"
            return
        fi
        
        local uid=$(echo "$user_info" | cut -d':' -f3)
        local gid=$(echo "$user_info" | cut -d':' -f4)
        local home=$(echo "$user_info" | cut -d':' -f6)
        local shell=$(echo "$user_info" | cut -d':' -f7)
        local full_name=$(echo "$user_info" | cut -d':' -f5)
        
        local last_changed="Permission Denied"
        if [ $(id -u) -eq 0 ]; then
            last_changed=$(chage -l "$username" | grep "Last password change" | cut -d':' -f2 | xargs)
        fi
        
        printf "%-20s %-40s\n" "Field" "Value"
        printf "%-20s %-40s\n" "Username" "$username"
        printf "%-20s %-40s\n" "User ID" "$uid"
        printf "%-20s %-40s\n" "Group ID" "$gid"
        printf "%-20s %-40s\n" "Home Directory" "$home"
        printf "%-20s %-40s\n" "Shell" "$shell"
        printf "%-20s %-40s\n" "Full Name" "$full_name"
        printf "%-20s %-40s\n" "Password Last Changed" "$last_changed"
        
        log "Detailed information for user $username displayed." "INFO"
    else
        lastlog | awk 'NR>1 {if ($3 ~ /Never/) $4="Never logged in"; else $4=$3; printf "%-12s %-30s\n", $1, $4}'
        log "User logins listed." "INFO"
    fi
}

time_range() {
    # Read the time arguments into an array
    local args=($@)

    if [ ${#args[@]} -eq 2 ]; then
        start_date="${args[0]}"
        end_date="${args[1]}"
    elif [ ${#args[@]} -eq 1 ]; then
        start_date="${args[0]}"
        end_date=$(date '+%Y-%m-%d')
    else
        echo "Time range takes one or two arguments"
        exit 1
    fi

    if time_range_is_valid "$start_date" "$end_date"; then
        if journalctl --since="$start_date" --until="$end_date" > /dev/null 2>&1; then
            echo "Showing activities from $start_date to $end_date:"
            journalctl --since="$start_date" --until="$end_date"
            log "Activities from $start_date to $end_date displayed." "INFO"
        else
            echo "No activities found from $start_date to $end_date."
            log "No activities found from $start_date to $end_date." "INFO"
        fi
    else
        echo "Invalid time range"
    fi
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -p|--port) shift; list_port "$1"; exit 0 ;;
        -d|--docker) shift; list_docker_objects "$1"; exit 0 ;;
        -n|--nginx) shift; list_nginx "$1"; exit 0 ;;
        -u|--users) shift; list_users "$1"; exit 0 ;;
        -t|--time)
            shift
            time_args=()
            while [[ "$#" -gt 0 && "$1" != -* ]]; do
                time_args+=("$1")
                shift
            done
            time_range "${time_args[@]}"
            exit 0
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo -e "Invalid option: $1\n"; usage; exit 1 ;;
    esac
done
usage

