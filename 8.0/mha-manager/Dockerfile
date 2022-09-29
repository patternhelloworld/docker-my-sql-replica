FROM ubuntu:18.04
RUN apt-get update -qqy && apt-get -qqy install \
curl runit wget unzip vim openssh-server

RUN sed -i "s/PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config
RUN sed -i -E "s/(PubkeyAuthentication).+$/\1 yes/" /etc/ssh/sshd_config

ENTRYPOINT /bin/bash