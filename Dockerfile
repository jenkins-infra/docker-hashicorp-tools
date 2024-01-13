# Golang is required for terratest
# Alpine is used by default for fast and ligthweight customization
ARG GO_VERSION=1.21.6
ARG PACKER_VERSION=1.10.0
ARG UPDATECLI_VERSION=v0.70.0
ARG JENKINS_INBOUND_AGENT_VERSION=3198.v03a_401881f3e-1

FROM golang:"${GO_VERSION}-alpine" AS gosource
FROM hashicorp/packer:"${PACKER_VERSION}" AS packersource
FROM updatecli/updatecli:"${UPDATECLI_VERSION}" AS updatecli
FROM jenkins/inbound-agent:"${JENKINS_INBOUND_AGENT_VERSION}"-alpine-jdk17
USER root

## Always use latest package versions (except for tools that should be pinned of course)
# hadolint ignore=DL3018
RUN apk add --no-cache \
  # To allow easier CLI completion + running shell scripts with array support
  bash \
  # Used to download binaries (implies the package "ca-certificates" as a dependency)
  curl \
  # Required to ensure GNU conventions for tools like "date"
  coreutils \
  # Dev. Tooling packages (e.g. tools provided by this image installable through Alpine Linux Packages)
  git \
  # dependency for jq
  oniguruma \
  # Dev workflow
  make \
  # Required for aws-cli and azure-cli
  pipx \
  # Used to unarchive Terraform downloads
  unzip \
  # yq for the yaml in /cleanup/*.sh
  yq~=4

# Get latest 1.6.x 'jq' for x86_64
ARG JQ_VERSION=1.6
RUN curl --silent --show-error --verbose --location --output /usr/local/bin/jq \
    https://github.com/jqlang/jq/releases/download/jq-"${JQ_VERSION}"/jq-linux64 \
  && chmod a+x /usr/local/bin/jq

## bash need to be installed for this instruction to work as expected
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Golang (for terratest)
COPY --from=gosource /usr/local/go/ /usr/local/go/
# .local/bin is for pipx
ENV PATH /usr/local/go/bin:/home/jenkins/.local/bin:$PATH

# Packer
COPY --from=packersource /bin/packer /usr/local/bin/

## Repeating the ARG to add it into the scope of this image
ARG GO_VERSION=1.21.6
ARG PACKER_VERSION=1.10.0
ARG UPDATECLI_VERSION=v0.70.0

## Install AWS CLI
ARG AWS_CLI_VERSION=1.32.18
RUN su - jenkins -c "pipx install awscli==${AWS_CLI_VERSION} --pip-args='--no-cache-dir'"

### Install Terraform CLI
# Retrieve SHA256sum from https://releases.hashicorp.com/terraform/<TERRAFORM_VERSION>/terraform_<TERRAFORM_VERSION>_SHA256SUMS
# For instance: "
# TERRAFORM_VERSION=X.YY.Z
# curl -sSL https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_$TERRAFORM_VERSION_SHA256SUMS | grep linux_amd64
ARG TERRAFORM_VERSION=1.6.6
RUN curl --silent --show-error --location --output /tmp/terraform.zip \
  "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
  && unzip /tmp/terraform.zip -d /usr/local/bin \
  && rm -f /tmp/terraform.zip \
  && terraform --version | grep "${TERRAFORM_VERSION}"

### Install trivy CLI
ARG TRIVY_VERSION=0.48.2
RUN apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing trivy~="${TRIVY_VERSION}" \
  && trivy --help

### Install golangcilint CLI
ARG GOLANGCILINT_VERSION=1.55.2
RUN curl --silent --show-error --location --fail \
  https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
  | sh -s -- -b "/usr/local/bin" "v${GOLANGCILINT_VERSION}"

### Install updatecli
COPY --from=updatecli /usr/local/bin/updatecli /usr/local/bin/updatecli

## Install Azure CLI
ARG AZ_CLI_VERSION=2.56.0
# hadolint ignore=DL3013,DL3018
RUN apk add --no-cache --virtual .az-build-deps gcc musl-dev python3-dev libffi-dev openssl-dev cargo make \
  && apk add --no-cache py3-pynacl py3-cryptography \
  && su - jenkins -c "pipx install azure-cli==${AZ_CLI_VERSION} --pip-args='--no-cache-dir'" \
  && apk del .az-build-deps

# Install doctl
ARG DOCTL_VERSION=1.102.0
RUN curl --silent --show-error --location --output /tmp/doctl.tar.gz\
    "https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-amd64.tar.gz" \
  && tar zxf /tmp/doctl.tar.gz -C /usr/local/bin/ \
  && rm -f /tmp/doctl.tar.gz \
  && chmod +x /usr/local/bin/doctl \
  && doctl version | grep -q "${DOCTL_VERSION}"

USER jenkins

## As per https://docs.docker.com/engine/reference/builder/#scope, ARG need to be repeated for each scope
ARG JENKINS_INBOUND_AGENT_VERSION=3198.v03a_401881f3e-1

LABEL io.jenkins-infra.tools="aws-cli,azure-cli,doctl,golang,golangci-lint,jenkins-inbound-agent,jq,packer,terraform,trivy,updatecli,yq"
LABEL io.jenkins-infra.tools.terraform.version="${TERRAFORM_VERSION}"
LABEL io.jenkins-infra.tools.golang.version="${GO_VERSION}"
LABEL io.jenkins-infra.tools.packer.version="${PACKER_VERSION}"
LABEL io.jenkins-infra.tools.golangci-lint.version="${GOLANGCILINT_VERSION}"
LABEL io.jenkins-infra.tools.aws-cli.version="${AWS_CLI_VERSION}"
LABEL io.jenkins-infra.tools.updatecli.version="${UPDATECLI_VERSION}"
LABEL io.jenkins-infra.tools.jenkins-inbound-agent.version="${JENKINS_INBOUND_AGENT_VERSION}"
LABEL io.jenkins-infra.tools.azure-cli.version="${AZ_CLI_VERSION}"
LABEL io.jenkins-infra.tools.doctl.version="${DOCTL_VERSION}"
LABEL io.jenkins-infra.tools.trivy.version="${TRIVY_VERSION}"
LABEL io.jenkins-infra.tools.jq.version="${JQ_VERSION}"

ENTRYPOINT ["/usr/local/bin/jenkins-agent"]
