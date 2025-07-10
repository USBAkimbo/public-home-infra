# What is this?
- Terraform for Proxmox
- Ansible to configure Ubuntu VMs
- Kubernetes using Talos Linux for apps
- All Linux shell commands assume you are root unless otherwise stated

# GitHub Actions self-hosted runner
- For this, I followed the GitHub Actions self-hosted runner installer for Linux
- My runner is an Ubuntu 22.04 LXC container that I manually created on my Proxmox host
- Note that the IP of the LXC container will need firewall access to the hosts you want to configure
- [I followed these docs to install the runner as a service](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service)
- This runner is only really used for Terraform in Proxmox as Terraform Cloud has to be logged into manually

# Terraform user account for Proxmox
- You need a Terraform user account on your Proxmox host for it to work
- [Follow the docs for this](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
- If you're using a self-hosted runner and Terraform Cloud, you need to do a `terraform login` on the runner
- This isn't ideal and I haven't found a better solution yet

# Cloud init Ubuntu 22.04 image creation commands
- [Read the docs as always](https://pve.proxmox.com/wiki/Cloud-Init_Support)
```
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
apt install guestfs-tools
virt-customize -a jammy-server-cloudimg-amd64.img --install qemu-guest-agent
qm create 9000 --name ci-template --memory 2048 --net0 virtio,bridge=vmbr2 --scsihw virtio-scsi-pci
qm set 9000 --scsi0 local-lvm:0,import-from=/root/jammy-server-cloudimg-amd64.img
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot order=scsi0
qm set 9000 --serial0 socket --vga serial0
qm template 9000
```

# Required GitHub Actions secrets
- Set the following secrets so your actions work

| Secret                 | Description                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------- |
| ANSIBLE_VAULT_PASSWORD | Password to decrypt your Ansible Vault encrypted files                                   |
| PM_API_URL             | Proxmox API URL                                                                          |
| PM_USER                | Proxmox Terraform user                                                                   |
| PM_PASSWORD            | Proxmox Terraform user password                                                          |
| SSH_HOST_KEY           | Ansible SSH private key in base64 format (will also automatically dos2unix the file too) |

# Create a new Ansible Vault secret
```
ansible-vault encrypt_string 'your text here'
```

# Ansible command to patch Proxmox hosts
```
cd ansible
ansible-playbook -i hosts --vault-password-file ~/.ansible/vault-pass actions-playbooks/ansible-proxmox-patches.yml
```

# Ansible command to configure parents server
```
cd ansible
ansible-playbook -i hosts --vault-password-file ~/.ansible/vault-pass actions-playbooks/ansible-parents-server.yml
```

# Talos Linux on Proxmox for K8s
- [Talos Linux is used to run the K8s cluster](https://www.talos.dev/latest/talos-guides/install/virtualized-platforms/proxmox/)
- A custom Talos ISO is also used
- [See the docs for this](https://www.talos.dev/latest/talos-guides/install/boot-assets/#image-factory)
- This is required to support the qemu guest agent and the required components for Longhorn

# Talos Linux install
- Go to https://factory.talos.dev/
- Use the wizard to select the following
  - siderolabs/amdgpu-firmware
  - siderolabs/amd-ucode
  - siderolabs/i915-ucode
  - siderolabs/intel-ice-firmware
  - siderolabs/intel-ucode
  - siderolabs/iscsi-tools
  - siderolabs/qemu-guest-agent
  - siderolabs/util-linux-tools
- These extensions allow for better CPU support, qemu agent support and NFS storage support
- This will give you an ID, such as `a44ca58b65602c48398f2f3eb0b2b03fe5b431e6dfd7b4ee7b8ee3ad53802de7` (this generally persists through versions too)
- Download the metal ISO and store it on each Proxmox node
- On each Proxmox node, create a new VM with, for example, 8 CPUs, 16GB of RAM and a 500GB disk (will also be used for Longhorn data)
- Connect the VM NIC to your K8s network
- Boot the installer and follow the docs to install
- These were my commands
```
# Install/upgrade Talosctl on your admin machine
sudo rm /usr/local/bin/talosctl
curl -sL https://talos.dev/install | sh

# Define vars
mkdir talos && cd talos

export NODE1="10.10.3.11"
export NODE2="10.10.3.12"
export NODE3="10.10.3.13"
export NODE4="10.10.3.14"
export TALOSCONFIG="talosconfig/talosconfig"

# Generate cluster config
talosctl gen config talos-proxmox-cluster https://$NODE1:6443 --output-dir talosconfig

# Move Talos config to home folder path
mv talosconfig/talosconfig ~/.talos/config

# Create a copy of the kubeconfig in the talosconfig folder (needed for backup)
talosctl kubeconfig talosconfig

# Edit the controlplane.yaml to allow control planes to be used as workers too
sed -i 's/# allowSchedulingOnControlPlanes: true/allowSchedulingOnControlPlanes: true/' _out/controlplane.yaml

# Edit the control plane and worker config install section to use the custom iso as per the docs
  install:
    disk: /dev/sda # The disk used for installations.
    image: factory.talos.dev/installer/a44ca58b65602c48398f2f3eb0b2b03fe5b431e6dfd7b4ee7b8ee3ad53802de7:v1.10.4

# Once you've updated the worker and controlplane, update them in KeePass
# Ensure that you backup all files in the _out folder

# Set config endpoint for Talos
talosctl config endpoint $NODE1
talosctl config node $NODE1

# Apply config to each node (this will reboot each node)
talosctl apply-config --insecure --nodes $NODE1 --file talosconfig/controlplane.yaml
talosctl apply-config --insecure --nodes $NODE2 --file talosconfig/controlplane.yaml
talosctl apply-config --insecure --nodes $NODE3 --file talosconfig/controlplane.yaml
talosctl apply-config --insecure --nodes $NODE4 --file talosconfig/worker.yaml

# Bootstrap the cluster to start it using $NODE1
talosctl bootstrap

# Export kubeconfig to default location `~/.kube/config`
# This will use $NODE1 for connections as multiple are not supported
talosctl kubeconfig
```

- Give it some time and your cluster should be up

# Install Kubectl
- [Install kubectl on your admin machine](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
```
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
```
- Configure `alias k=kubectl`
- Check if you can see the nodes with `k get nodes`
- You should see something like this
```
# k get nodes
NAME         STATUS   ROLES           AGE   VERSION
p-h-k8s-01   Ready    control-plane   38h   v1.29.3
p-h-k8s-02   Ready    control-plane   38h   v1.29.3
p-h-k8s-03   Ready    control-plane   20m   v1.29.3
p-h-k8s-04   Ready    worker          20m   v1.29.3
```

# Important! Backup configs
- Encrypt and backup all the files in the `_out` folder
- These files are **very** important so don't lose them
- They also contain secrets, so don't store them in Git

# Upgrade Talos nodes
- To upgrade a node from (for example) 1.7.0 to 1.7.4, re-install `talosctl` using the above link to get the latest version
- Then go to the factory link above and build a new image (making sure to select the qemu agent and the other extensions)
- If the image hash has changed, switch to that
- If not, use the one below and change the version tag
- Then run the upgrade 1 node at a time with a 10 minute gap between nodes to allow for data syncing
```
talosctl upgrade -n $NODE1 -n $NODE2 -n $NODE3 --image factory.talos.dev/installer/a44ca58b65602c48398f2f3eb0b2b03fe5b431e6dfd7b4ee7b8ee3ad53802de7:v1.10.4
```
- IMPORTANT! Update the `controlplane.yaml` and `worker.yaml` files with these links too

# Kubernetes config
- The below is all in logical order as if you're starting from scratch
- [Also see the API reference docs (these should be easier to find ffs)](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.30/)
- I have a rule as well - anything that could break the cluster DOES NOT go in ArgoCD

# Install K9s
- Cluster viewer from the CLI
- Seriously, this thing is awesome for exploring the cluster or just doing a little admin work
- https://k9scli.io/
- https://github.com/derailed/k9s/releases
```
LATEST_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)
wget https://github.com/derailed/k9s/releases/download/$LATEST_VERSION/k9s_linux_amd64.deb
sudo dpkg -i k9s_linux_amd64.deb
rm k9s_linux_amd64.deb
```

# Install Helm
```
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

# Install Metal LB
- Required for ingress to work so you can connect to `myapp.mydomain.com` which is running in your cluster
- Kubes is cloud native and expects an auto-provisioned external load balancer
- This is THE project for running a load balancer in the cluster and it works extremely well
```
# https://metallb.universe.tf/installation/

# Install (but check for an update first)
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml

# Apply configs (wait for pods to be ready first)
k apply -f kubernetes/manual/metal-lb
```

# Install Nginx Ingress Controller
- Required so `myapp.mydomain.com` can be routed to the correct K8s service
```
# https://kubernetes.github.io/ingress-nginx/deploy/#quick-start
helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace

# Patch nginx to apply SSL passthrough to work for ArgoCD
kubectl -n ingress-nginx patch deployment/ingress-nginx-controller --patch-file kubernetes/manual/nginx-ingress-controller/enable-ssl.yml
```

# Install cert-manager
- Required for automated SSL certs for `myapp.mydomain.com`
```
# https://cert-manager.io/docs/installation/helm/
helm upgrade --install cert-manager cert-manager --repo https://charts.jetstack.io --namespace cert-manager --create-namespace --version v1.18.1 --set installCRDs=true

# See the repo for the secrets and issuer configs
```

# ArgoCD config
- Required for automated Git CI/CD
```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/install.yaml

# Edit the secret in the argo folder, then run
kubectl apply -f kubernetes/manual/argocd
```
- Then get the admin login
```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```
- You should now be able to log in and change the password
- Argo uses an `ApplicationSet` to deploy everything in the `kubernetes/apps` folder
- It also deploys Helm charts by "faking" a manifest that includes the actual helm chart as a dependency

# Allow containers with NET_ADMIN in default namespace
- This allows containers like Gluetun to get net admin for WireGuard
```
# https://www.talos.dev/latest/kubernetes-guides/configuration/pod-security/
# This will allow containers in the "default" namespace to use NET_ADMIN
kubectl label ns default pod-security.kubernetes.io/enforce=privileged
```

# Install Longhorn
- Required for replicated local cluster storage
- "But why not just use NFS or something?"
- Because SQLite locks up and the DB can corrupt on NFS shares
- Low storage latency is required for some apps to function properly too
- Each node has 500GB disks and Longhorn uses that storage under `/var/lib/longhorn`
- Read the docs
- https://longhorn.io/docs/latest/advanced-resources/os-distro-specific/talos-linux-support/
- Ensure the Talos `controlplane.yml` and `worker.yml` files are updated with the correct image and machine config as described in the docs
- https://longhorn.io/docs/latest/deploy/install/install-with-kubectl/
- The manifest in the `kubernetes/manual/longhorn` folder in my repo has the installer along with my tweaks
  - 1 replica of each volume per node
  - Prefer to schedule the storage on the node that the app is running on
```
# Install using manifest in my repo
# Ensure you update it using the latest release from the repo
# https://github.com/longhorn/longhorn/releases
kubectl apply -f kubernetes/manual/longhorn

# Also set the pod security for the namespace otherwise Longhorn won't start
kubectl label namespace longhorn-system pod-security.kubernetes.io/enforce=privileged
```
- Once the above is done, you should now have a reachable Longhorn web UI and a storage class
- You want local storage, so Longhorn should keep 1 replica of a volume on each node
- To set this, go into the `Longhorn UI --> Settings --> General --> Backup Target --> Replica Node Level Soft Anti-Affinity --> Tick enabled`
- This prevents Lognhorn from doing something like "I need 4 replicas so 2 will go on node 1 and 2 will go on node 2"
- Also set `Replica Auto Balance` to `best-effort` to ensure even distribution of replicas across nodes
- Then modify `longhorn.yml` and `numberOfReplicas` to match the number of nodes in your cluster
- Then set `dataLocality: "best-effort"`
- These 2 settings ensure that at least 1 replica will be on each node
- And `best-effort` means it will try to use the local replica
- If you want to limit what nodes your replicas will run on, you can label the nodes and then edit the daemonset deployment to node select your label
- Note that this will not apply to existing volumes - you need to fix them in the web UI (Longhorn is buggy, so if they fail to replicate, back them up, delete them then restore them, or backup the files in the volume and restore another way)
- The storage class can be treated like any other storage class, so just create your PVCs for your deployments using the Longhorn storage class

# Longhorn backups via NFS
- Longhorn can auto backup volumes to NFS
- You absolutely 100% need this as the cluster could be trashed, but TrueNAS wont be
- Go into the Longhorn UI --> Settings --> General --> Backup Target
- Set the NFS backup location to `nfs://10.10.3.2:/mnt/ssd/longhorn-backups`
- Then go to the "Recurring Job" page and create a recurring backup job that runs daily
- Ensure you select the `default` tag to backup all volumes
- Note that this does block level backups, not file level, so if you need to restore you must do it via Longhorn
- Not sure if I like this so I will consider file level backups using a cron job that mounts the volumes as read only and does an rsync to my NAS

# Install cadvisor
- Required to scrape container metrics
```
# Install Kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash

# Deploy cadvisor
# https://github.com/google/cadvisor/releases
VERSION=v0.49.1
kustomize build "https://github.com/google/cadvisor/deploy/kubernetes/base?ref=${VERSION}" | kubectl apply -f -

# Allow pods to run as privileged
kubectl label ns cadvisor pod-security.kubernetes.io/enforce=privileged
```

# Kubeseal config
- https://github.com/bitnami-labs/sealed-secrets?tab=readme-ov-file#installation
- https://github.com/bitnami-labs/sealed-secrets/releases
- Install the controller with ArgoCD
- Install the CLI from the docs
- Create your `secret.yml` as you normally would, but don't commit it to the repo
- Encrypt your secrets using `kubeseal`
```
kubeseal < path/to/secret.yml > path/to/sealedsecret.yml
```
- Your sealed secret will be in the same folder and can be applied by Argo and committed to the repo

# Backup Kubeseal cert
- Kubeseal works by generating a key pair and storing it in the K8s cluster
- The CLI grabs the `kubeseal` public key and encrypts secrets with it
- If your cluster breaks, your `sealedsecrets` will not be readable as the private key is lost
- To prevent this, backup the key
```
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key.yaml
```
- Save `sealed-secrets-key.yaml` to KeePass under `Kubeseal Private Key` as an attachment

# Restore Kubeseal key from backup
- Use this command if you've just re-installed Kubeseal and you want to re-use your key
```
# Save sealed-secrets-key.yaml to a file
kubectl apply -f sealed-secrets-key.yaml

# Restart sealed secrets controller
kubectl delete pod -n kube-system -l name=sealed-secrets-controller
```

# Decrypt a sealed secret offline
- First follow the above steps to get the key or get it from KeePass
- Then edit your sealed secret and ensure you're using the JSON syntax highlighting in VS Code
- Ensure you have no formatting errors or it won't decrypt
- Decrypt using this command
```
kubeseal --recovery-unseal --recovery-private-key sealed-secrets-key.yaml < kubernetes/path/to/sealedsecret.yml
```
- Then you just need to decode the secrets with `base64`
```
echo "text" | base64 -d
```

# GitHub Actions Runner Controller
- Self hosted GitHub runners in Kubes
```
# https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller
# https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/using-actions-runner-controller-runners-in-a-workflow
# https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/authenticating-to-the-github-api#deploying-using-personal-access-token-classic-authentication

# Apply secret
kubectl create ns arc-systems
kubectl create ns arc-runners
kubectl apply -f kubernetes/manual/arc-runners/sealedsecret.yml

# Install the runner controller (watches for jobs)
NAMESPACE="arc-systems"
helm install arc \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

# Install the runner scale set (the containers that run jobs)
INSTALLATION_NAME="arc-runner-set"
NAMESPACE="arc-runners"
GITHUB_PAT="token"
helm upgrade "${INSTALLATION_NAME}" \
    --install \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set githubConfigSecret.github_token="${GITHUB_PAT}" \
    --values kubernetes/manual/arc-runners/values.yaml \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```
- Useful issues page on uninstall if you need it, but just try a `k delete ns <namespace> --force` first
- https://github.com/actions/actions-runner-controller/issues/2781

# Namespace stuck terminating
- Do you have a namespace that just says terminating and it won't die?
- It's probably because of the CRDs
- First, check the docs of the thing you're trying to remove
- Failing that, you should be able to clean them up with the below commands
- These 2 articles were useful for Longhorn
- https://avasdream.engineer/kubernetes-longhorn-stuck-terminating
- https://longhorn.io/docs/latest/deploy/uninstall/#uninstalling-longhorn-using-kubectl
```
# Set var
NAMESPACE=longhorn-system

# List all resources
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n $NAMESPACE

# Patch all resources in the namespace and set ther finalizers to null
for crd in $(kubectl get crd -o name | grep $NAMESPACE); do kubectl patch $crd -p '{"metadata":{"finalizers":[]}}' --type=merge; done;

# Hard namespace kill
kubectl proxy &
kubectl get namespace $NAMESPACE -o json | jq '.spec = {"finalizers":[]}' > temp.json
curl -k -H "Content-Type: application/json" -X PUT --data-binary @temp.json 127.0.0.1:8001/api/v1/namespaces/$NAMESPACE/finalize
rm temp.json
pkill -f "kubectl proxy"
```

# Unifi Network Application MongoDB config
- For Unifi's MongoDB to work, run the deployment as normal
- Ensure your permissions for the DB folder are `999:999` (needed for the DB to run)
- Once the DB is up, exec into it (use k9s)
```
k exec -it unifi-db-xxxx -- sh
```
- Now create the DB config by pasting this in
```
mongosh <<EOF
use ${MONGO_AUTHSOURCE}
db.auth("${MONGO_INITDB_ROOT_USERNAME}", "${MONGO_INITDB_ROOT_PASSWORD}")
db.getSiblingDB("unifi").createUser({user: "unifi", pwd: "unifi", roles: [{role: "readWrite", db: "unifi"}]});
db.getSiblingDB("unifi_stat").createUser({user: "unifi", pwd: "unifi", roles: [{role: "readWrite", db: "unifi_stat"}]});
EOF

mongosh <<EOF
use ${MONGO_AUTHSOURCE}
db.auth("${MONGO_INITDB_ROOT_USERNAME}", "${MONGO_INITDB_ROOT_PASSWORD}")
db.createUser({
  user: "${MONGO_USER}",
  pwd: "${MONGO_PASS}",
  roles: [
    { db: "${MONGO_DBNAME}", role: "dbOwner" },
    { db: "${MONGO_DBNAME}_stat", role: "dbOwner" },
    { db: "${MONGO_DBNAME}_audit", role: "dbOwner" }
  ]
})
EOF
```
- Once this is done, Unifi should just start
- My initial attempt to restore my config backup from my old Unifi Controller failed as the upload just kept failing
- You can run through the setup to create a new instance, then once you're logged in you can go to the settings and restore
- This restore also failed for me via ingress for some weird reason
- To get around this I just did a `k port-forward unifi-blah 8443` to access it
- Restoring through that worked

# Frigate basic auth
- [Useful docs on basic auth from Kubes](https://kubernetes.github.io/ingress-nginx/examples/auth/basic/)

# Force deployment to run on a specific node with node labels
- [First you need to label the node](https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes/#before-you-begin)
```
# Show all labels
kubectl get nodes --show-labels

kubectl label nodes p-h-k8s-04 frigate=allowed
kubectl label nodes p-h-k8s-04 immich=allowed
kubectl label nodes p-h-k8s-04 download=allowed
kubectl label nodes p-h-k8s-04 zabbixdb=allowed
```
- Then use it in your deployment
```
spec:
  template:
    spec:
      nodeSelector:
        key: value
```

# Run a container for testing on a specific node
```
kubectl run -ti --rm test --image=ubuntu:22.04 --overrides='{"spec": { "nodeSelector": {"kubernetes.io/hostname": "p-h-k8s-01"}}}'
```

# Zabbix monitoring
- https://www.zabbix.com/integrations/kubernetes#kubernetes_http
- My install is different to the docs
- I've used Argo to deploy Zabbix without the Zabbix proxy - it's just the Zabbix server, web and DB with a daemonset for the agents
- There's a service account that's required with this
- To get the service account for Zabbix, run the following command to create a token that lasts 1 year
```
k create token zabbix-readonly --duration=8766h
```
- This token is used in the Zabbix UI with the following
  - Create a host entry for your control plane node(s)
  - Apply the templates as-per the docs
  - This will monitor pretty much everything it can find in the cluster
- This also needs the kube-state-metrics which is already installed via the ApplicationSet controller

# Quick run krr in a container
- Ensure you have Prom installed and it's collected a few weeks of data to be accurate
- Run an Ubuntu container
```
k run --rm -it --image ubuntu:22.04 krr-temp -- bash
```
- And then run this
```bash
# Install requirements
apt update && apt upgrade -y && apt install python3 python3-pip curl git gpg nano -y

# Clone and cd to repo
git clone https://github.com/robusta-dev/krr && cd krr

# Install pip requirements
pip install -r requirements.txt

# Copy your kubeconfig in
mkdir  ~/.kube/
nano ~/.kube/config

# Run krr and point at the prometheus helm chart service
python3 krr.py simple -p http://prometheus-server
```
