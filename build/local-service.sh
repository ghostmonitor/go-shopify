#!/bin/bash

set -e

export LOCAL_ARCH="linux/arm64"

if [ -f .env ]; then
  env=$(env)
  if [ "$(uname)" = 'Linux' ]; then
    vars=$(grep -v '^#' .env | xargs -d '\n')
  else # BSD
    vars=$(grep -v '^#' .env | xargs -0)
  fi

  for v in $vars
  do
    n=$(echo $v | cut -f1 -d=)
    if ! grep -q "${n}" <<< "${env}"; then
      export $v
    fi
  done
fi

export NPM_TOKEN=${NPM_TOKEN:-""}
export MONGO_HOST=${MONGO_HOST:-localhost}

function service() {
  if grep -q "${1}:$" docker-compose.yaml; then
    echo -n "${1}"
  else
    echo -n ""
  fi
}

if [ "x$1" = "xdown" ]; then
  docker compose down
else
  SERVICES=()
  SERVICES+=($(service mongodb))  # standalone mongodb instance
  SERVICES+=($(service mongo-rs)) # mongodb replica set
  SERVICES+=($(service redis))
  SERVICES+=($(service dynamodb))

  if [ ${#SERVICES[@]} -eq 0 ]; then
    echo "No services to start"
    exit 0
  fi

  echo "Starting local services: ${SERVICES[@]}"
  docker compose up -d --build ${SERVICES[@]}
  sleep 3

  for c in $(docker compose ps -q)
  do 
    IMG=$(docker container inspect $c --format='{{.Config.Image}}')
    PORTS=$(docker container inspect $c --format='{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}} {{end}}')

    for p in ${PORTS}
    do
      until nc -vz localhost "$p"
      do
        echo "Waiting for ${IMG}:${p} to become available..."
        sleep 3
      done
    done
  done
fi
