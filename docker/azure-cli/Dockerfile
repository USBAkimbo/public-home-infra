FROM ubuntu:24.04
RUN apt update && apt upgrade -y
RUN apt install curl wget openssh-server -y
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash
RUN az extension add --name ssh
RUN az extension add --name bastion
