#!/bin/bash

# Include prettytable
source ./prettytable.sh

# Setup logging
LOG_FILE="./devopsfetch.log"
LOG_MAX_SIZE=10485760 # 10 MB
LOG_ROTATE_COUNT=5

if [[ $EUID -eq 0 ]]; then
    LOG_FILE="/var/log/devopsfetch.log"
    LOG_DIR="/var/log"
else
    LOG_FILE="./devopsfetch.log"
    LOG_DIR=$(dirname "$LOG_FILE")
fi

# Create the log file directory if not exists
mkdir -p "$LOG_DIR"

log() {
    local msg="$1"
    local level="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $level - $msg" >> "$LOG_FILE"
}

monitor() {
    local interval="$1"
    
    while true; do
        echo "Starting monitoring cycle at $(date)" >> "$LOG_FILE"
        
        {
            list_port ""
            list_docker_objects ""
            list_nginx ""
            list_users ""
        } >> "$LOG_FILE" 2>&1

        log "Monitoring cycle completed." "INFO"

        # Wait for the specified interval before the next cycle
        sleep "$interval"
    done
}

log_rotate() {
    if [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE") -ge $LOG_MAX_SIZE ]]; then
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local old_log_file="${LOG_FILE}_${timestamp}.old"
        
        echo "Rotating log file." >> "$LOG_FILE"
        
        mv "$LOG_FILE" "$old_log_file"
        
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi
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
        
        {
            echo -e "Field\tValue"
            echo -e "User\t$user"
            echo -e "Port\t$listening_port"
            echo -e "Service\t$service"
            echo -e "Port Type\t$port_type"
            echo -e "Process ID\t$pid"
        } | prettytable 2
    else
        lsof_output=$(lsof -P -n -i | grep '(LISTEN)' 2>/dev/null)
        if [ -z "$lsof_output" ]; then
            echo "No open ports found."
            return
        fi
        
        {
            echo -e "USER\tPORT\tSERVICE"
            echo "$lsof_output" | while IFS= read -r line; do
                service=$(echo "$line" | awk '{print $1}')
                user=$(echo "$line" | awk '{print $3}')
                port=$(echo "$line" | awk -F'[ :]' '{print $(NF-1)}')
                
                printf "%-15s \t %-15s \t %-30s\n" "$user" "$port" "$service"
            done
        } | prettytable 3
        
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
        
        {
            echo -e "Field\tValue"
            echo -e "ID\t$id"
            echo -e "Name\t$name"
            echo -e "Created At\t$created"
            echo -e "Path\t$path"
            echo -e "Args\t$args"
            echo -e "Image\t$image"
        } | prettytable 2
        
        log "Detailed information for container $container_name displayed." "INFO"
    else
        local images=$(docker images --format "{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}" 2>/dev/null)
        local containers=$(docker ps -a --format "{{.ID}}\t{{.Image}}\t{{.Command}}\t{{.CreatedAt}}\t{{.Status}}\t{{.Names}}" 2>/dev/null)
        
        {
            echo -e "Repository\tTag\tID\tCreated Since"
            echo "$images"
        } | prettytable 4
        
        echo "-----------------------------------------------------------------------------------------------------"
        
        {
            echo -e "ID\tImage\tCommand\tCreated At\tStatus\tNames"
            echo "$containers"
        } | prettytable 6
        
        log "Docker images and containers listed." "INFO"
    fi
}

list_nginx() {
    local domain="$1"
    local nginx_conf_dirs=('/etc/nginx/sites-enabled' '/etc/nginx/sites-available' '/etc/nginx/conf.d')
    local table=$(mktemp)
    
    printf "%-20s\t%-40s\t%-40s\n" "Domain" "Proxy" "Config File" > "$table"
    
    for conf_dir in "${nginx_conf_dirs[@]}"; do
        if [ ! -d "$conf_dir" ]; then
            continue
        fi
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
                    echo -e "$server_name\t$proxy\t$conf_file" >> "$table"
                done
            done
        done
    done
    
    if [ -n "$domain" ] && [ $(wc -l < "$table") -eq 1 ]; then
        echo "No configuration found for domain $domain."
    else
        cat "$table" | prettytable 3
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
        
        {
            echo -e "Field\tValue"
            echo -e "Username\t$username"
            echo -e "User ID\t$uid"
            echo -e "Group ID\t$gid"
            echo -e "Home Directory\t$home"
            echo -e "Shell\t$shell"
            echo -e "Full Name\t$full_name"
            echo -e "Password Last Changed\t$last_changed"
        } | prettytable 2
        
        log "Detailed information for user $username displayed." "INFO"
    else
        {
            echo -e "USER\tLAST LOGIN"
            lastlog | while IFS= read -r line; do
                # Skip the header line
                if [[ "$line" == Username* ]]; then
                    continue
                fi
                
                line=$(echo "$line" | awk '{$1=$1;print}')
                
                IFS=' ' read -r -a array <<< "$line"
                
                username="${array[0]}"
                last_login="${line#${username}}"
                last_login=$(echo "$last_login" | xargs) 

                # Check if last login time contains "**Never logged in**"
                if [[ "$last_login" == "**Never logged in**" ]]; then
                    last_login="Never logged in"
                fi
                
                printf "%-15s\t%-30s\n" "$username" "$last_login"
            done
        } | prettytable 2
        
        log "User logins listed." "INFO"
    fi
}

time_range() {
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
        -i|--interval)
            shift
            if [[ "$#" -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
                monitor "$1"
            else
                echo "Invalid interval. Please provide a numeric value for interval in seconds."
                exit 1
            fi
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo -e "Invalid option: $1\n"; usage; exit 1 ;;
    esac
done

usage
