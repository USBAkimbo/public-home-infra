FROM ubuntu:24.04
RUN apt update && apt upgrade -y
RUN apt install wget -y
RUN wget https://github.com/librespeed/speedtest-cli/releases/download/v1.0.10/librespeed-cli_1.0.10_linux_amd64.tar.gz
RUN tar -xvf librespeed-cli_1.0.10_linux_amd64.tar.gz
RUN rm -f librespeed-cli_1.0.10_linux_amd64.tar.gz
RUN mkdir /speedtest