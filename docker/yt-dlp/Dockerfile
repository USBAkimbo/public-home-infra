FROM ubuntu:24.04
RUN apt update && apt upgrade -y
RUN apt install software-properties-common -y
RUN add-apt-repository ppa:tomtomtom/yt-dlp -y
RUN apt update
RUN apt install yt-dlp ffmpeg -y
