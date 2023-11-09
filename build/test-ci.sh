#!/bin/sh

REGISTRY_ID="${AWS_ECR_REGISTRY_ID:?AWS_ECR_REGISTRY_ID env var is required}"
REGION=${AWS_DEFAULT_REGION:-"us-east-1"}
if [ "${CI}" = "true" ]; then
AWS_ECR_LOGIN="${AWS_ECR_LOGIN:-0}"
else
AWS_ECR_LOGIN="${AWS_ECR_LOGIN:-1}"
fi

if [ "${AWS_ECR_LOGIN}" = "1" ]; then 
	aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${REGISTRY_ID}.dkr.ecr.${REGION}.amazonaws.com"
fi
DOCKER_BUILDKIT=0 MONGO_HOSTNAME=${MONGO_HOSTNAME:-mongo-rs} docker compose up --abort-on-container-exit --build

