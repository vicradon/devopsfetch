# DevOpsFetch

`DevOpsFetch` is a server monitoring tool designed to provide comprehensive details about running ports, processes, Docker containers, Nginx domains, users, and time. It is a useful tool for DevOps professionals to monitor and manage their systems efficiently.

## Table of Contents

1. [Cloning locally](##Cloning-locally)
1. [Installation and Configuration](##installation-and-configuration)
1. [Usage Examples](##usage-examples)
1. [Logging Mechanism](##logging-mechanism)
1. [Retrieving Logs](###retrieving-logs)

## Clonning locally

You can clone the project by running the command below:

```sh
git clone https://github.com/vicradon/devopsfetch.git
cd devopsfetch
```

## Installation and Configuration

To install and configure `DevOpsFetch`, follow these steps:

### 1. Prepare the Environment

Ensure you have the necessary permissions and environment for installation. You will need `sudo` privileges to perform the installation.

### 2. Download and Install

1. **Run the installation script:**

   ```bash
   sudo bash install.sh
   ```

This script sets up the logging, installs the `devopsfetch` tool, creates a systemd service, and configures log rotation.

## Usage Examples

Once installed, `devopsfetch` can be run with various command-line flags. Here are examples of how to use it:

### Basic Usage

Return users and their last login time

```bash
bash devopsfetch.sh -u # returns users and their last log in time

┌─────────────────────┬────────────────────────────────┐
│USER                 │LAST LOGIN                      │
├─────────────────────┼────────────────────────────────┤
│root                 │Never logged in                 │
│daemon               │Never logged in                 │
│bin                  │Never logged in                 │
│sys                  │Never logged in                 │
│rabbitmq             │Never logged in                 │
│hammed               │Never logged in                 │
└─────────────────────┴────────────────────────────────┘
```

Return all active ports

```sh
bash devopsfetch.sh --port

┌──────────────────┬───────────────────┬─────────────────────────────────┐
│USER              │PORT               │SERVICE                          │
├──────────────────┼───────────────────┼─────────────────────────────────┤
│user              │ 27182             │ MathWorks                       │
│user              │ 44987             │ MathWorks                       │
│user              │ 1716              │ kdeconnec                       │
│user              │ 8828              │ code                            │
│user              │ 3000              │ node                            │
│user              │ 8829              │ code                            │
└──────────────────┴───────────────────┴─────────────────────────────────┘
```

Return details about a specific port

```sh
bash devopsfetch.sh --port 3000

┌────────────┬───────┐
│Field       │Value  │
├────────────┼───────┤
│User        │user   │
│Port        │3000   │
│Service     │node   │
│Port Type   │TCP    │
│Process ID  │82934  │
└────────────┴───────┘
```

## Logging Mechanism

`devopsfetch` logs actions and outputs to a file `/var/log/devopsfetch.log` when it is run as root and `./devopsfetch.log` when it is run as normal user.

### Continuous monitoring mode

You can implement devopsfetch with continuous monitoring so that it continuously logs it's output to a log file given an interval in seconds. The log file is also rorated after it reaches a set size (10 MB).

You can run it with continuous monitoring which will run all the services using the command below:

```sh
bash devopsfetch.sh -i 30 # continuously runs the script and logs output every 30 seconds
```

### Retrieving Logs

You can retrieve logs by catting the log file

```sh
cat /var/log/devopsfetch.log
```
