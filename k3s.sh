#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
INTERNAL_IP=$(hostname -I | cut -d' ' -f1)
ROLE=""
MASTER_IP=""
handle_error() {
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            INSTALL="true"
            shift
            ;;
        --uninstall)
            INSTALL="false"
            shift
            ;;
        --master)
            ROLE="master"
            shift
            ;;
        --agent)
            ROLE="agent"
            shift
            ;;
        --token=*)
            K3S_TOKEN="${1#*=}"
            shift
            ;;
        --master-ip=*)
            MASTER_IP="${1#*=}"
            shift
            ;;
        --cluster-cidr=*)
            CLUSTER_CIDR="${1#*=}"
            shift
            ;;
        --service-cidr=*)
            SERVICE_CIDR="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [ -z "$ROLE" ]; then
    handle_error "Specify what k3s node is this either --master or --agent."
    exit 1
fi

if [ -z "$INSTALL" ]; then
    handle_error "Specify what you want to do either --install or --uninstall."
    exit 1
fi

ping -c 1 google.com > /dev/null 2>&1
if [ $? -ne 0 ]; then
    handle_error "No internet connectivity."
    exit 1
fi

initialization() {
    echo -e "${GREEN}Howdy 👋! Please wait, We are setting up the $ROLE node${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    if [ $? -ne 0 ]; then
        handle_error "Failed to update packages."
    fi

    apt-get upgrade -y
    if [ $? -ne 0 ]; then
        handle_error "Failed to upgrade packages."
    fi

    apt-get install curl -y
    if [ $? -ne 0 ]; then
        handle_error "Failed to install curl."
    fi

    apt-get install wget -y
    if [ $? -ne 0 ]; then
        handle_error "Failed to install wget."
    fi

    nvidia-smi
    if [ $? -ne 0 ]; then
        handle_error "${RED}NVIDIA Drivers are not installed on the machine.${NC}"
    fi

    nvidia-ctk --version
    if [ $? -ne 0 ]; then
        echo -e "${GREEN}NVIDIA Container Toolkit not found installing...${NC}"
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg   && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |     sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |     sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list   &&     sudo apt-get update
        nvidia-ctk --version
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}NVIDIA Container Toolkit is installed.${NC}"
        else
            handle_error "Failed to install NVIDIA Container Toolkit."
            exit 1
        fi
    fi

    nvcc --version
    if [ $? -ne 0 ]; then
        echo -e "${GREEN}CUDA Toolkit not found installing...${NC}"
        apt-get install gcc -y
        wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
        dpkg -i cuda-keyring_1.1-1_all.deb
        apt-get update
        apt-get -y install cuda
        nvcc --version
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}CUDA Toolkit is installed.${NC}"
        else
            handle_error "Failed to install NVIDIA Container Toolkit."
            exit 1
        fi
    fi

    # ufw enable
    # ufw allow 8472/udp
    # ufw allow 10250/tcp
    # ufw allow 51820/udp
    # ufw allow 51821/udp
}

# Function to install HAProxy for master
install_haproxy() {
    echo -e "${GREEN}Installing HAProxy...${NC}"
    apt install haproxy -y
    if [ $? -ne 0 ]; then
        handle_error "Failed to install HAProxy."
        exit 1
    fi

    # Configure HAProxy
    echo "frontend master" >> /etc/haproxy/haproxy.cfg
    echo "    bind *:8080" >> /etc/haproxy/haproxy.cfg
    echo "    mode tcp" >> /etc/haproxy/haproxy.cfg
    echo "    option tcplog" >> /etc/haproxy/haproxy.cfg
    echo "    default_backend kube-apiserver" >> /etc/haproxy/haproxy.cfg
    echo "" >> /etc/haproxy/haproxy.cfg
    echo "backend kube-apiserver" >> /etc/haproxy/haproxy.cfg
    echo "    mode tcp" >> /etc/haproxy/haproxy.cfg
    echo "    option tcplog" >> /etc/haproxy/haproxy.cfg
    echo "    option tcp-check" >> /etc/haproxy/haproxy.cfg
    echo "    balance roundrobin" >> /etc/haproxy/haproxy.cfg
    echo "    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100" >> /etc/haproxy/haproxy.cfg
    echo "    server master $INTERNAL_IP:6443" >> /etc/haproxy/haproxy.cfg

    # Restart HAProxy
    systemctl restart haproxy
    if [ $? -ne 0 ]; then
        handle_error "Failed to restart HAProxy."
        exit 1
    fi
    systemctl enable haproxy
}

# Function to install K3s for master
install_k3s_master() {
    # ufw allow 6443/tcp
    K3S_COMMAND="curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE='644' sh -s - server --tls-san=$INTERNAL_IP"

    if [ -n "$CLUSTER_CIDR" ]; then
        K3S_COMMAND+=" --cluster-cidr=$CLUSTER_CIDR"
    fi

    if [ -n "$SERVICE_CIDR" ]; then
        K3S_COMMAND+=" --service-cidr=$SERVICE_CIDR"
    fi

    echo -e "${GREEN}Running K3s master setup...${NC}"
    eval "$K3S_COMMAND"
    if [ $? -eq 0 ]; then
        echo "K3s master setup is completed."
    else
        handle_error "Failed to run K3s master setup."
        exit 1
    fi

    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml >> ~/.bashrc

    echo -e "${GREEN}Installing K8S cli tools...${NC}"
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh

    if [ $? -ne 0 ]; then
        handle_error "Failed to install helm."
        exit 1
    fi

    snap install kubectx --classic
    if [ $? -ne 0 ]; then
        handle_error "Failed to install Kubectx."
        exit 1
    fi

    echo -e "${GREEN}Adding Kubectl Auto Complete...${NC}"
    source <(kubectl completion bash)
    echo "source <(kubectl completion bash)" >> ~/.bashrc

    alias k=kubectl
    complete -o default -F __start_kubectl k
}

# Function to install K3s for agent
install_k3s_agent() {
    if [ -z "$MASTER_IP" ]; then
        handle_error "Master's IP address is required for the agent. Use --master-ip=x.x.x.x."
        exit 1
    fi

    if [ -z "$K3S_TOKEN" ]; then
        handle_error "K3S token is required for the agent. The server token is written to /var/lib/rancher/k3s/server/token in master node. use --token=<Secret Token> with \"\""
        exit 1
    fi
    echo -e "${GREEN}Running K3s agent setup...${NC}"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent --server https://$MASTER_IP:8080 --token $K3S_TOKEN" sh -s -
    if [ $? -eq 0 ]; then
        echo "${GREEN}K3s agent setup is completed.${NC}"
    else
        handle_error "Failed to run K3s agent setup."
        exit 1
    fi
}

post_script() {
    systemctl is-active containerd
    if [ $? -ne 0 ]; then
        echo -e "${GREEN}Containerd not found installing...${NC}"
        apt-get -y install containerd -y
        systemctl is-active containerd
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Containerd is installed.${NC}"
            systemctl enable containerd
        else
            handle_error "Failed to install Containerd."
            exit 1
        fi
    fi

    #nvidia-ctk runtime configure --runtime=containerd
    if [ $? -ne 0 ]; then
        handle_error "Failed to install Containerd."
        exit 1
    fi

    systemctl restart containerd
    if [ $? -ne 0 ]; then
        handle_error "Failed to restart containerd."
        exit 1
    fi
}

install_applications() {
    echo -e "${GREEN}Installing ArgoCD...${NC}"
    helm repo add argo https://argoproj.github.io/argo-helm
    helm upgrade --install argocd argo/argo-cd
}

remove_haproxy() {
    echo -e "${GREEN}Removing HAProxy...${NC}"
    apt-get purge --auto-remove haproxy -y
    if [ $? -ne 0 ]; then
    handle_error "Failed to delete HAProxy."
    fi
}

remove_server() {
  echo -e "${GREEN}Removing K3S server...${NC}"
  /usr/local/bin/k3s-uninstall.sh
  if [ $? -ne 0 ]; then
    handle_error "Failed to remove K3S server."
    exit 1
  fi
}

remove_agent() {
  echo -e "${GREEN}Removing K3S agent...${NC}"
  /usr/local/bin/k3s-agent-uninstall.sh
  if [ $? -ne 0 ]; then
    handle_error "Failed to remove K3S agent."
    exit 1
  fi
}

if [ "$INSTALL" == "true" ]; then
    initialization
    if [ "$ROLE" == "master" ]; then
        install_haproxy
        install_k3s_master
        post_script
        install_applications
        echo -e "${GREEN}It's done! Enjoy!...${NC}"
    elif [ "$ROLE" == "agent" ]; then
        install_k3s_agent
        post_script
        echo -e "${GREEN}It's done! Enjoy!...${NC}"
    fi
elif [ "$INSTALL" == "false" ]; then
    if [ "$ROLE" == "master" ]; then
        remove_haproxy
        remove_server
        echo -e "${GREEN}It's done! Enjoy!...${NC}"
    elif [ "$ROLE" == "agent" ]; then
        remove_agent
        echo -e "${GREEN}It's done! Enjoy!...${NC}"
    fi
fi