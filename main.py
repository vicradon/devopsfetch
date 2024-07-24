#!/usr/bin/env python3

import argparse
import subprocess
import datetime
import os
import logging
import psutil
import socket
import re
import pwd
import spwd
import json
from prettytable import PrettyTable

# Setup logging
# LOG_FILE = '/var/log/devopsfetch.log'
LOG_FILE = './devopsfetch.log'
logging.basicConfig(filename=LOG_FILE, level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def get_service_name(port, proto):
    try:
        service = socket.getservbyport(port, proto)
    except OSError:
        service = 'unknown'
    return service

def scan_ports():
    result = []
    
    # Iterate over all TCP connections
    for conn in psutil.net_connections(kind='inet'):
        pid = conn.pid
        if pid:
            process = psutil.Process(pid)
            user = process.username()
            service = get_service_name(conn.laddr.port, 'tcp')
            result.append((user, conn.laddr.port, service))
    
    # Iterate over all UDP connections
    for conn in psutil.net_connections(kind='inet6'):
        pid = conn.pid
        if pid:
            process = psutil.Process(pid)
            user = process.username()
            service = get_service_name(conn.laddr.port, 'udp')
            result.append((user, conn.laddr.port, service))
    
    return result

def time_range_is_valid(start_date, end_date):
    """ Validate that start time is before end time and both are not in the future. """
    try:
        start_date = datetime.datetime.strptime(start_date, '%Y-%m-%d')
        end_date = datetime.datetime.strptime(end_date, '%Y-%m-%d')
        now = datetime.datetime.now()

        if start_date > end_date:
            print("Error: Start date must be before or equal to end date.")
            return False

        if start_date > now or end_date > now:
            print("Error: Start and end dates must not be in the future.")
            return False

        return True

    except ValueError as e:
        print(f"Invalid date format: {e}")
        return False
    
# def list_ports(port_number):
#     if port_number:
#         result = subprocess.run(['ss', '-tuln', f'| grep {port_number}'], shell=True, capture_output=True, text=True)
#         print(result.stdout)
#         logging.info(f"Information for port {port_number} displayed.")
#     else:
#         result = subprocess.run(['ss', '-tuln'], capture_output=True, text=True)
#         print(result.stdout)
#         logging.info("Active ports listed.")

def list_port(port=None):
    try:
        command = ['lsof', '-i', '-P', '-n']
        if port:
            command.extend(['-i', f':{port}'])
        
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        lsof_output = result.stdout.strip()

        if not lsof_output:
            print(f"No open ports found.")
            return

        table = PrettyTable()
        table.field_names = ["USER", "PORT", "SERVICE"]

        # Skip the first line which is the header
        for line in lsof_output.splitlines()[1:]:
            parts = line.split()
            user = parts[2]
            port_service = parts[0]
            service_type = parts[-2]
            service_address = parts[8]
            listening_port = None

            print(parts)
            # continue

            print("->" in service_address, service_address)

            if "->" in service_address:
                local_section = service_address.split('->')[0]
                local_section.split(':')[1]
            else:
                pattern = r'\*:(\d+)\s'
                match = re.search(pattern, service_address)
                if match:
                    listening_port = match.group(1)
                    

            table.add_row([user, listening_port, port_service])

        
        print(table)
        logging.info(f"Ports listed.")
    
    except subprocess.CalledProcessError as e:
        print("Error running lsof command.")
        logging.error(f"An error occurred while running lsof: {e}")
    except Exception as e:
        print("An error occurred while processing ports.")
        logging.error(f"An unexpected error occurred: {e}")


def list_docker_objects(container_name=None):
    if container_name:
        try:
            result = subprocess.run(['docker', 'inspect', container_name], capture_output=True, text=True, check=True)
            container_info = json.loads(result.stdout)

            if not container_info:
                print(f"No information found for container {container_name}.")
                return

            # Extract the first container's info (since inspect returns a list)
            container = container_info[0]

            # Prepare the table
            table = PrettyTable()
            table.field_names = ["Field", "Value"]

            # Define the fields to extract
            fields = {
                "ID": container.get("Id"),
                "Name": container.get("Name"),
                "Created At": container.get("Created"),
                "Path": container.get("Path"),
                "Args": container.get("Args"),
                "Image": container.get("Image")
            }

            # Add fields to the table
            for field, value in fields.items():
                if value is None:
                    value = "N/A"
                table.add_row([field, value])

            print(table)
            logging.info(f"Detailed information for container {container_name} displayed.")


        except subprocess.CalledProcessError as e:
            print("Error running docker inspect command.")
            logging.error(f"An error occurred while running docker inspect: {e}")
        except json.JSONDecodeError as e:
            print("Error decoding JSON output.")
            logging.error(f"An error occurred while decoding JSON output: {e}")
        except Exception as e:
            print("An error occurred while processing container information.")
            logging.error(f"An unexpected error occurred: {e}")
    else:
        try:
            # Docker Images
            result = subprocess.run(['docker', 'images', '--format', '{{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}'], capture_output=True, text=True, check=True)
            images_info = result.stdout.strip().split('\n')
            
            image_table = PrettyTable()
            image_table.field_names = ["Repository", "Tag", "ID", "Created Since"]
            for line in images_info:
                parts = line.split('\t')
                if len(parts) == 4:
                    image_table.add_row(parts)
            
            print("Docker Images")
            print(image_table)

            # Docker Containers
            result = subprocess.run(['docker', 'ps', "-a", '--format', '{{.ID}}\t{{.Image}}\t{{.Command}}\t{{.CreatedAt}}\t{{.Status}}\t{{.Names}}'], capture_output=True, text=True, check=True)
            containers_info = result.stdout.strip().split('\n')
            
            container_table = PrettyTable()
            container_table.field_names = ["ID", "Image", "Command", "Created At", "Status", "Names"]
            for line in containers_info:
                parts = line.split('\t')
                if len(parts) == 6:
                    container_table.add_row(parts)
            
            print("Docker Containers")
            print(container_table)

            logging.info("Docker images and containers listed.")
        except subprocess.CalledProcessError as e:
            print("Error running docker command.")
            logging.error(f"An error occurred while running docker command: {e}")
        except Exception as e:
            print("An error occurred while processing Docker information.")
            logging.error(f"An unexpected error occurred: {e}")

def list_nginx(domain=None):
    nginx_conf_dirs = ['/etc/nginx/sites-enabled', '/etc/nginx/conf.d']
    table = PrettyTable()
    table.field_names = ["Domain", "Proxy", "Config File"]

    def extract_domains_proxies(conf_content):
        server_name_pattern = re.compile(r'\s*server_name\s+([^;]+);')
        proxy_pass_pattern = re.compile(r'\s*proxy_pass\s+http://([^;]+);')
        server_names = server_name_pattern.findall(conf_content)
        proxies = proxy_pass_pattern.findall(conf_content)
        if not server_names:
            server_names = ['default']
        if not proxies:
            proxies = ['N/A']
        return server_names, proxies

    try:
        for conf_dir in nginx_conf_dirs:
            for conf_file in os.listdir(conf_dir):
                conf_path = os.path.join(conf_dir, conf_file)
                with open(conf_path) as f:
                    conf_content = f.read()
                server_names, proxies = extract_domains_proxies(conf_content)
                for server_name in server_names:
                    exact_match = False
                    for sn in server_name.split():
                        if sn == domain:
                            exact_match = True
                            break
                    if domain and not exact_match:
                        continue
                    for proxy in proxies:
                        table.add_row([server_name, proxy, conf_path])
        if table.rowcount == 0 and domain:
            print(f"No configuration found for domain {domain}.")
        else:
            print(table)
            logging.info("Nginx domains and proxies listed.")
    except Exception as e:
        logging.error(f"An error occurred: {e}")

def list_users(username=None):
    if username:
        try:
            user_info = pwd.getpwnam(username)
            user_details = {
                "Username": user_info.pw_name,
                "User ID": user_info.pw_uid,
                "Group ID": user_info.pw_gid,
                "Home Directory": user_info.pw_dir,
                "Shell": user_info.pw_shell,
                "Full Name": user_info.pw_gecos,
            }
            try:
                shadow_info = spwd.getspnam(username)
                user_details["Password Last Changed"] = shadow_info.sp_lstchg
            except PermissionError:
                user_details["Password Last Changed"] = "Permission Denied"

            table = PrettyTable()
            table.field_names = ["Field", "Value"]
            for field, value in user_details.items():
                table.add_row([field, value])
            print(table)
            logging.info(f"Detailed information for user {username} displayed.")
        except KeyError:
            print(f"No detailed information found for user {username}.")
            logging.info(f"No detailed information found for user {username}.")
    else:
        try:
            result = subprocess.run(['lastlog'], capture_output=True, text=True, check=True)
            users_info = result.stdout


            table = PrettyTable()
            table.field_names = ["Username", "Last Login Time"]

            for line in users_info.splitlines()[1:]:  # Skip header line
                    parts = line.split()
                    username = parts[0]
                    last_login = parts[3] if len(parts) > 3 else "Unknown"
                    
                    if "**Never logged in**" in line:
                        last_login = "Never logged in"
                    
                    table.add_row([username, last_login])
                
            print(table)
            logging.info("User logins listed.")
        except subprocess.CalledProcessError as e:
            print("Error running lastlog command.")
            logging.error(f"An error occurred while running lastlog: {e}")
        except Exception as e:
            print("An error occurred while processing user logins.")
            logging.error(f"An unexpected error occurred: {e}")

def time_range(start_date, end_date):
    try:
        # Convert string inputs to datetime objects
        start_date = datetime.datetime.strptime(start_date, '%Y-%m-%d')
        end_date = datetime.datetime.strptime(end_date, '%Y-%m-%d')

        command = [
            'journalctl',
            '--since', start_date,
            '--until', end_date
        ]
        
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        logs = result.stdout.strip()


        if logs:
            print(f"Showing activities from {start_date} to {end_date}:")
            print(logs)
        else:
            print(f"No activities found from {start_date} to {end_date}.")

        logging.info(f"Activities from {start_date} to {end_date} displayed.")

    except subprocess.CalledProcessError as e:
        print("Error running journalctl command.")
        logging.error(f"An error occurred while running journalctl: {e}")
    except ValueError as e:
        print(f"Invalid date format: {e}")
        logging.error(f"Invalid date format: {e}")
    except Exception as e:
        print("An error occurred while processing log entries.")
        logging.error(f"An unexpected error occurred: {e}")


def main():
    parser = argparse.ArgumentParser(description='A handy tool for Server Information Retrieval and Monitoring', usage='%(prog)s [options]')
    parser.add_argument('-p', '--port', nargs='?', const=True, help='Display active ports or details for a specific port')
    parser.add_argument('-d', '--docker', nargs='?', const=True, help='List Docker images or details for a specific container')
    parser.add_argument('-n', '--nginx', nargs='?', const=True, help='Display Nginx domains or details for a specific domain')
    parser.add_argument('-u', '--users', nargs='?', const=True, help='List users or details for a specific user')
    parser.add_argument('-t', '--time', type=str, nargs="+", help='Display activities within a specified time range')
    
    args = parser.parse_args()


    if args.port:
        if args.port is not None:
            if args.port is True:
                list_port()
            else:
                list_port(args.port)
    elif args.docker:
        if args.docker is not None:
            if args.docker is True:
                list_docker_objects()
            else:
                list_docker_objects(args.docker)
    elif args.nginx is not None:
        if args.nginx is True:
            list_nginx()
        else:
            list_nginx(args.nginx)
    elif args.users is not None:
        if args.users is True:
            list_users()
        else:
            list_users(args.users)
    elif args.time:
        start_time, end_time = None, None

        if len(args.time) == 2:
            start_time = args.time[0]
            end_time = args.time[1]
        elif len(args.time) == 1:
            start_time = args.time[0]
            end_time = datetime.datetime.now().strftime('%Y-%m-%d')
        else:
            parser.print_help()
            
        if time_range_is_valid(start_time, end_time):
            time_range(start_time, end_time)
        else:
            parser.print_help()

    else:
        parser.print_help()

if __name__ == "__main__":
    main()
