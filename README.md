# Configure K3S cluster using script

## Purpose:

The primary purpose of this script is to automate the installation and configuration of a K3s cluster on a Ubuntu machine, supporting both master and agent nodes. It also provides options for uninstalling the cluster components. The script takes command-line arguments to specify the role (master or agent) and the operation (install or uninstall).


## Requirements to Run the Script:

### Bash Shell:


- The script is written in Bash, so a Bash-compatible shell is required.

### Internet Connectivity:


- The machine should have internet connectivity to download and install necessary packages.

### Permissions:


- The user running the script should have sufficient permissions to install packages and configure system settings.

### Master Node Details (for agent installation):


- When installing an agent, details such as the master's IP address (--master-ip) and a valid K3s token (--token) are required. 
- For master's-ip and K3S token run following command on master node 
    - Master-IP: ```hostname -I | cut -d' ' -f1```
    - K3S Token: ```cat /var/lib/rancher/k3s/server/token```

### Dependencies:


- Dependencies like curl, wget, NVIDIA drivers, CUDA Toolkit, and Containerd should be available on the machine.

### Supported Operating System:


- The script assumes compatibility with Debian-based systems (Ubuntu, etc.). Adjustments may be needed for other distributions.

## Running the Script:


To run the script, execute it with appropriate command-line arguments:

```
./script.sh --install --master --cluster-cidr=<CIDR> --service-cidr=<CIDR>
```

NOTE: cluster-cider and service-cider is optional

To uninstall components

```
./script.sh --uninstall --master
```

Adjust the arguments based on the desired installation or uninstallation scenario and the role of the node (master or agent).

```
./script.sh --install --agent --master-ip=<master-ip> --token=<token>
```


## Key Components:

### Initialization:

- Updates and upgrades the system packages.

- Installs essential tools like curl, wget, and checks for NVIDIA drivers and Containerd.

### Command-line Argument Parsing:

- Parses command-line arguments to determine the role (master/agent), operation (install/uninstall), and additional parameters like --token, --master-ip, --cluster-cidr, and --service-cidr.

### Internet Connectivity Check:

- Verifies internet connectivity by attempting to ping Google. The script exits if there is no internet connection.

### Installation Functions:

- install_haproxy:

    - Installs and configures HAProxy for the master node.

- install_k3s_master:

    - Installs K3s on the master node and configures Kubernetes-related tools like Helm and kubectx.

- install_k3s_agent:

    - Installs K3s on the agent node, requiring the master's IP and a K3s token for authentication.

- Post-Installation Steps:

    - Configures Containerd if not found.

    - Restarts Containerd.

- Additional Applications:

    - Installs ArgoCD using Helm.

### Uninstallation Functions:

- remove_haproxy:

    - Purges HAProxy from the system.

- remove_server:

    - Uninstalls K3s server components.

- remove_agent:

    - Uninstalls K3s agent components.

### Conclusion:

The script concludes by displaying a success message, indicating the completion of the installation or uninstallation process.
