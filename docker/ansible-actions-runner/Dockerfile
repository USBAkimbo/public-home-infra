FROM ghcr.io/actions/actions-runner:latest
RUN sudo apt update && sudo apt upgrade -y
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | sudo bash -
RUN sudo apt install software-properties-common git curl wget dos2unix nodejs -y
RUN sudo add-apt-repository --yes --update ppa:ansible/ansible
RUN sudo apt install ansible -y