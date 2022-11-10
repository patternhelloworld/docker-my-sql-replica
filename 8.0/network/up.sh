#!bin/bash
if [[ $(docker images -q hello-world 2> /dev/null) == '' ]]
then
    echo "[NOTICE] create a 'hello-world' image to set up the network"
    docker load -i hello-world.tar
fi

docker-compose down
docker-compose up -d