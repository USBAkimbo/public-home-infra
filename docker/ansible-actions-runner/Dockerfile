FROM ghcr.io/actions/actions-runner:latest
RUN sudo apt update && sudo apt upgrade -y
RUN sudo apt install software-properties-common git curl wget dos2unix -y
RUN sudo add-apt-repository --yes --update ppa:ansible/ansible
RUN sudo apt install ansible -y