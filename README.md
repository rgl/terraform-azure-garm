# About

This is a [GitHub Actions Runners Manager (garm)](https://github.com/cloudbase/garm) playground running in Azure.

This shows how to create a [Azure Container Instances Container Group](https://docs.microsoft.com/en-us/azure/container-instances/container-instances-container-groups) with [Caddy (for Let's Encrypt TLS Certificate)](https://hub.docker.com/_/caddy) reverse proxy to the internal garm container.

This is wrapped in a vagrant environment to make it easier to play with this stack without changing your local machine.

After you follow the usage steps, the following components will be running:

![](architecture.png)

## Usage

If you are using Hyper-V, [configure Hyper-V in your local machine](https://github.com/rgl/windows-vagrant#hyper-v-usage).

If you are using libvirt, you should already known what to do.

The following steps will show how to use garm to manage self-hosted runners, use
them in a single user repository, and in all the repositories of a single
organization.

At your GitHub user account, create a new repository, in this example, its
called `terraform-azure-garm-example-repository`, then clone, add, and push
the following content:

```bash
# see https://github.com/rgl/terraform-azure-garm-example-repository
git clone git@github.com:rgl/terraform-azure-garm-example-repository.git
pushd terraform-azure-garm-example-repository
install -d .github/workflows
cat >.github/workflows/build.yml <<'EOF'
name: build
on:
  - push
  - workflow_dispatch
jobs:
  build:
    name: Build
    runs-on: garm-azure-amd64-ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - name: linux
        run: uname -a
      - name: os
        run: cat /etc/os-release
      - name: environment variables
        run: env | sort
      - name: current user
        run: id
      - name: sudo user
        run: sudo id
      - name: network interfaces
        run: ip addr
      - name: df
        run: df -h
      - name: installed packages
        run: dpkg -l
      - name: running applications
        run: ps auxww
      - name: working directory
        run: pwd
      - name: working directory files
        run: find -type f
EOF
cat >README.md <<'EOF'
# About

[![build](https://github.com/rgl/terraform-azure-garm-example-repository/actions/workflows/build.yml/badge.svg)](https://github.com/rgl/terraform-azure-garm-example-repository/actions/workflows/build.yml)
EOF
git add .
git commit -m init
git push
popd
```

Repeat the process, but in the context of the `rgl-example` organization:

```bash
# see https://github.com/rgl-example/terraform-azure-garm-org-example-repository
git clone git@github.com:rgl-example/terraform-azure-garm-org-example-repository.git
pushd terraform-azure-garm-org-example-repository
install -d .github/workflows
cat >.github/workflows/build.yml <<'EOF'
name: build
on:
  - push
  - workflow_dispatch
jobs:
  build:
    name: Build
    runs-on: garm-org-azure-amd64-ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - name: linux
        run: uname -a
      - name: os
        run: cat /etc/os-release
      - name: environment variables
        run: env | sort
      - name: current user
        run: id
      - name: sudo user
        run: sudo id
      - name: network interfaces
        run: ip addr
      - name: df
        run: df -h
      - name: installed packages
        run: dpkg -l
      - name: running applications
        run: ps auxww
      - name: working directory
        run: pwd
      - name: working directory files
        run: find -type f
EOF
cat >README.md <<'EOF'
# About

[![build](https://github.com/rgl-example/terraform-azure-garm-org-example-repository/actions/workflows/build.yml/badge.svg)](https://github.com/rgl-example/terraform-azure-garm-org-example-repository/actions/workflows/build.yml)
EOF
git add .
git commit -m init
git push
popd
```

Create the vagrant environment:

```bash
vagrant up --no-destroy-on-error
```

Enter the created vagrant environment:

```bash
vagrant ssh
```

Login into azure:

```bash
az login

# list the subscriptions.
az account list --all
az account show

# set the subscription.
export ARM_SUBSCRIPTION_ID="<YOUR-SUBSCRIPTION-ID>"
az account set --subscription "$ARM_SUBSCRIPTION_ID"
az account show
```

Provision the azure infrastructure:

```bash
cd /vagrant
export CHECKPOINT_DISABLE=1
export TF_LOG=TRACE
export TF_LOG_PATH="$PWD/terraform.log"
rm -f "$TF_LOG_PATH"
terraform init
terraform plan -out=tfplan
# NB beware of https://letsencrypt.org/docs/duplicate-certificate-limit/
time terraform apply tfplan
```

In a different shell, show the garm logs:

```bash
export ARM_SUBSCRIPTION_ID="<YOUR-SUBSCRIPTION-ID>"
# NB to show all the containers logs omit --container garm.
az container logs \
  --resource-group rgl-garm \
  --name garm \
  --container garm \
  --follow
```

Initialize garm:

```bash
# NB this creates the ~/.local/share/garm-cli/config.toml file.
# see https://github.com/cloudbase/garm/blob/main/doc/quickstart.md#initializing-garm
# see https://github.com/cloudbase/garm/releases
# renovate: datasource=github-releases depName=cloudbase/garm
garm_version="0.1.6"
rm -f garm-cli-linux-amd64.tgz garm-cli
wget -q "https://github.com/cloudbase/garm/releases/download/v$garm_version/garm-cli-linux-amd64.tgz"
tar xvf garm-cli-linux-amd64.tgz garm-cli
rm garm-cli-linux-amd64.tgz
./garm-cli profile delete garm # NB only required when garm was initialized in a previous test.
garm_admin_password="$(tr -dc 'A-Za-z0-9@#$%^&*()-_=+[]{}|;:,.<>?' < /dev/urandom | head -c 24)"
./garm-cli init \
  --name garm \
  --url "$(terraform output -raw url)" \
  --username admin \
  --email admin@example.com \
  --password "$garm_admin_password"
```

Add a user GitHub Personal Access Token (PAT):

```bash
# NB you need to go into your github account and create a new token at
#    https://github.com/settings/tokens. create a classic token with
#    the permissions described at:
#     https://github.com/cloudbase/garm/blob/v0.1.6/doc/github_credentials.md#adding-github-credentials
#    the pat should end up with the admin:repo_hook and repo scopes.
github_token="ghp_replace-with-the-rest-of-your-github-token"
./garm-cli github credentials add \
  --endpoint github.com \
  --name rgl \
  --description "GitHub PAT for the rgl user" \
  --auth-type pat \
  --pat-oauth-token "$github_token"
```

Add a user GitHub repository:

```bash
repo_name='terraform-azure-garm-example-repository'
./garm-cli repo add \
  --credentials rgl \
  --owner rgl \
  --name "$repo_name" \
  --install-webhook \
  --random-webhook-secret
repo_id="$(./garm-cli repo list --format json \
  | jq -r \
    --arg owner rgl \
    --arg name "$repo_name" \
    '.[] | select(.owner == $owner and .name == $name) | .id')"
```

Add a organization GitHub Personal Access Token (PAT), in these examples, we
use the `rgl-example` organization:

```bash
# NB you need to go into your github account and create a new token at
#    https://github.com/settings/tokens. create a classic token with
#    the permissions described at:
#     https://github.com/cloudbase/garm/blob/v0.1.6/doc/github_credentials.md#adding-github-credentials
#    the pat should end up with the admin:org, admin:org_hook, admin:repo_hook and repo scopes.
org_github_token="ghp_replace-with-the-rest-of-your-organization-github-token"
./garm-cli github credentials add \
  --endpoint github.com \
  --name rgl-example \
  --description "GitHub PAT for the rgl-example organization" \
  --auth-type pat \
  --pat-oauth-token "$org_github_token"
```

Add a GitHub organization:

```bash
org_name='rgl-example'
./garm-cli org add \
  --credentials rgl-example \
  --name "$org_name" \
  --install-webhook \
  --random-webhook-secret
org_id="$(./garm-cli org list --format json \
  | jq -r \
    --arg name "$org_name" \
    '.[] | select(.name == $name) | .id')"
```

Create a Ubuntu (runner) pool associated with a GitHub repository:

```bash
# NB for each github action job run, garm will create a vm (and related azure
#    resources) in a new (and ephemeral) azure resource group with the prefix
#    set with --runner-prefix, e.g., --runner-prefix rgl-garm, will create a
#    resource group named rgl-garm-r2BxRNWHNSV4.
# NB while I was testing this, each fresh runner took about 4m to execute the
#    example build job. when there was an idle runner available, it took about
#    20s.
# NB see prices at https://cloudprice.net/?region=francecentral&currency=EUR&sortField=linuxPrice&sortOrder=true&_memoryInMB_min=4&_memoryInMB_max=16&filter=Standard_F.%2B_v2&timeoption=month&columns=name%2CnumberOfCores%2CmemoryInMB%2CresourceDiskSizeInMB%2ClinuxPrice%2CwindowsPrice%2C__alternativevms%2C__savingsOptions%2CbestPriceRegion
# NB VM flavor Standard_F2s_v2 is 2 vCPU,  4 GB RAM. 16 GB Temp Disk. €0.0908/hour.  €66.25/month.
# NB VM flavor Standard_F4s_v2 is 4 vCPU,  8 GB RAM. 32 GB Temp Disk. €0.1815/hour. €132.49/month.
# NB VM flavor Standard_F8s_v2 is 8 vCPU, 16 GB RAM. 64 GB Temp Disk. €0.3630/hour. €264.98/month.
# NB you can list the available images using az cli as:
#     az vm image list --location northeurope --publisher Canonical --offer 0001-com-ubuntu-server-jammy --sku 22_04-lts-gen2 --output table
# NB instead of the latest image version we can use a specific version, e.g.,
#     Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:22.04.202206040.
./garm-cli pool create \
  --enabled true \
  --min-idle-runners 0 \
  --max-runners 2 \
  --tags garm-azure-amd64-ubuntu-22.04 \
  --repo "$repo_id" \
  --runner-prefix rgl-garm \
  --provider-name azure \
  --os-arch amd64 \
  --os-type linux \
  --flavor Standard_F2s_v2 \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest \
  --extra-specs '{
    "storage_account_type": "StandardSSD_LRS",
    "disk_size_gb": 127
  }'
pool_id="$(./garm-cli pool list "--repo=$repo_id" --format json | jq -r '.[] | .id')"
./garm-cli pool update \
  --min-idle-runners 1 \
  --max-runners 3 \
  "$pool_id"
./garm-cli runner list "$pool_id"
```

Go to the example repository and manually run the build workflow, e.g., click
the "Run workflow" button at:

https://github.com/rgl/terraform-azure-garm-example-repository/actions/workflows/build.yml

Then go into the Azure Portal, and observe the resources being created, and deleted.

You should also fiddle with the `--min-idle-runners` setting as exemplified above.

Create a Ubuntu (runner) pool associated with a GitHub organization:

```bash
# NB for each github action job run, garm will create a vm (and related azure
#    resources) in a new (and ephemeral) azure resource group with the prefix
#    set with --runner-prefix, e.g., --runner-prefix rgl-garm, will create a
#    resource group named rgl-garm-r2BxRNWHNSV4.
# NB while I was testing this, each fresh runner took about 4m to execute the
#    example build job. when there was an idle runner available, it took about
#    20s.
# NB see prices at https://cloudprice.net/?region=francecentral&currency=EUR&sortField=linuxPrice&sortOrder=true&_memoryInMB_min=4&_memoryInMB_max=16&filter=Standard_F.%2B_v2&timeoption=month&columns=name%2CnumberOfCores%2CmemoryInMB%2CresourceDiskSizeInMB%2ClinuxPrice%2CwindowsPrice%2C__alternativevms%2C__savingsOptions%2CbestPriceRegion
# NB VM flavor Standard_F2s_v2 is 2 vCPU,  4 GB RAM. 16 GB Temp Disk. €0.0908/hour.  €66.25/month.
# NB VM flavor Standard_F4s_v2 is 4 vCPU,  8 GB RAM. 32 GB Temp Disk. €0.1815/hour. €132.49/month.
# NB VM flavor Standard_F8s_v2 is 8 vCPU, 16 GB RAM. 64 GB Temp Disk. €0.3630/hour. €264.98/month.
# NB you can list the available images using az cli as:
#     az vm image list --location northeurope --publisher Canonical --offer 0001-com-ubuntu-server-jammy --sku 22_04-lts-gen2 --output table
# NB instead of the latest image version we can use a specific version, e.g.,
#     Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:22.04.202206040.
./garm-cli pool create \
  --enabled true \
  --min-idle-runners 0 \
  --max-runners 2 \
  --tags garm-org-azure-amd64-ubuntu-22.04 \
  --org "$org_id" \
  --runner-prefix rgl-garm-org \
  --provider-name azure \
  --os-arch amd64 \
  --os-type linux \
  --flavor Standard_F2s_v2 \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest \
  --extra-specs '{
    "storage_account_type": "StandardSSD_LRS",
    "disk_size_gb": 127
  }'
org_pool_id="$(./garm-cli pool list "--org=$org_id" --format json | jq -r '.[] | .id')"
./garm-cli pool update \
  --min-idle-runners 1 \
  --max-runners 3 \
  "$org_pool_id"
./garm-cli runner list "$org_pool_id"
```

Go to the example repository and manually run the build workflow, e.g., click
the "Run workflow" button at:

https://github.com/rgl-example/terraform-azure-garm-org-example-repository/actions/workflows/build.yml

Then go into the Azure Portal, and observe the resources being created, and deleted.

You should also fiddle with the `--min-idle-runners` setting as exemplified above.

Finally, when you are done with this, destroy the entire example.

Start by destroying the runners, then the pools, then the infrastructure:

```bash
./garm-cli pool update --min-idle-runners 0 "$pool_id"
./garm-cli pool update --min-idle-runners 0 "$org_pool_id"
# NB before continuing, go into azure and ensure there are no rgl-garm- prefixed
#    resource groups, those should have (or are still) been deleted by garm. be
#    patient, as it can take several minutes to finish.
./garm-cli runner list --all
./garm-cli pool list --all
./garm-cli pool delete "$pool_id"
./garm-cli pool delete "$org_pool_id"
./garm-cli pool list --all
./garm-cli repo list
./garm-cli repo delete "$repo_id"
./garm-cli repo list
./garm-cli org list
./garm-cli org delete "$org_id"
./garm-cli org list
terraform destroy
./garm-cli profile delete garm
```

List this repository dependencies (and which have newer versions):

```bash
GITHUB_COM_TOKEN='YOUR_GITHUB_PERSONAL_TOKEN' ./renovate.sh
```

## Caveats

* [There is no way to known the end-user client IP address](https://feedback.azure.com/d365community/idea/c81db3f3-0c25-ec11-b6e6-000d3a4f0858).
  * **NB** The ACI container is behind a load balancer that does not preserve the client IP address.

## Reference

* [azurerm_container_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_group)
* [Container groups in Azure Container Instances](https://docs.microsoft.com/en-us/azure/container-instances/container-instances-container-groups)
* [YAML reference: Azure Container Instances](https://docs.microsoft.com/en-us/azure/container-instances/container-instances-reference-yaml)
* [Caddy](https://github.com/caddyserver/caddy)
* [Caddy Docker Image](https://github.com/caddyserver/caddy-docker)
