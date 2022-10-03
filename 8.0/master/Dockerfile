FROM mysql:8.0.30-debian

RUN apt-get update -qqy && apt-get -qqy install \
iputils-ping curl runit wget unzip vim openssh-server ssh sshpass perl libdbi-perl libmodule-install-perl libdbd-mysql-perl make

WORKDIR /tmp
RUN wget https://github.com/yoshinorim/mha4mysql-node/releases/download/v0.58/mha4mysql-node-0.58.tar.gz && tar -zxf /tmp/mha4mysql-node-0.58.tar.gz -C /opt
WORKDIR /opt/mha4mysql-node-0.58
RUN perl Makefile.PL && make  && make install

RUN mkdir -p /usr/local/mha/log && mkdir -p /usr/local/mha/work

RUN sed -i -E "s/^[#\t\s]*(PermitRootLogin).+$/\1 yes/" /etc/ssh/sshd_config
RUN sed -i -E "s/^[#\t\s]*(PubkeyAuthentication).+$/\1 yes/" /etc/ssh/sshd_config
RUN sed -i -E "s/^[#\t\s]*(StrictHostKeyChecking).+$/\1 no/" /etc/ssh/ssh_config
