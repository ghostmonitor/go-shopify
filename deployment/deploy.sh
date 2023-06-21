#!/bin/bash
AWS_ECR_REGISTRY_ID="${AWS_ECR_REGISTRY_ID:?AWS_ECR_REGISTRY_ID env var is required}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
NAMESPACE="${1:?First parameter must be the namespace}"
SERVICE="${2:?Second parameter must be the service}"
TAG="${3:?Third parameter must be the docker tag}" # "${CIRCLE_TAG:-$CIRCLE_SHA1}"
CHART_NAME="${CHART_NAME:-service}"
CHART_VERSION_NUMBER="${CHART_VERSION_NUMBER:-2.9.0}"
TIMEOUT="${TIMEOUT:-15m}"
OWNER_TEAM_NAME="${OWNER_TEAM_NAME:-Platform}"

aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | helm registry login --username AWS --password-stdin "${AWS_ECR_REGISTRY_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"

set +e
HELM_CMD=""
HELM_PARAMS=""
HELM_JOB_ENABLED="true"
HELM_STATUS_CMD="helm status ${SERVICE} --namespace ${NAMESPACE}"
STATUS=$($HELM_STATUS_CMD -o json | jq -r '.info.status')
if [[ -z "${STATUS}" || "${STATUS}" == 'uninstalled' ]]; then
	HELM_CMD=install
	kubectl -n "${NAMESPACE}" annotate deploy,service,sa,hpa -l "app.kubernetes.io/name=${SERVICE}" "meta.helm.sh/release-name=${SERVICE}"
	kubectl -n "${NAMESPACE}"  annotate deploy,service,sa,hpa -l "app.kubernetes.io/name=${SERVICE}" "meta.helm.sh/release-namespace=${NAMESPACE}"
elif [[ "${STATUS}" == 'deployed' ]]; then
	HELM_CMD=upgrade
	HELM_PARAMS="--atomic "
elif [[ "${STATUS}" == 'failed' ]]; then
	HELM_CMD=upgrade
fi
HELM_JOB_COUNT=$(kubectl -n "${NAMESPACE}" get job -l "app.kubernetes.io/name=${SERVICE}" --ignore-not-found | wc -l)
if (( HELM_JOB_COUNT > 0 )); then
	HELM_JOB_ENABLED="false"
fi

if [[ -n "${HELM_CMD}" ]]; then
	echo "Download values file '${NAMESPACE}/${SERVICE}.yml' from S3 and ${HELM_CMD}"
	set -e
	aws s3 cp "s3://recart-application-config/${NAMESPACE}/${SERVICE}.yml" "./${SERVICE}.yml"
	set +e

	# Run Helm install/upgrade
	helm "${HELM_CMD}" "${SERVICE}" "oci://${AWS_ECR_REGISTRY_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${CHART_NAME}" \
		${HELM_PARAMS}--timeout "${TIMEOUT}" \
		--wait \
		--wait-for-jobs \
		--version "${CHART_VERSION_NUMBER}" \
		--namespace "${NAMESPACE}" \
		-f "./${SERVICE}.yml" \
		--set image.tag="${TAG}" \
		--set postInstallJob.enabled="${HELM_JOB_ENABLED}" \
		--set ownerTeam="${OWNER_TEAM_NAME}"
		HELM_RESULT=$?
		exit $HELM_RESULT
else
	echo "Cannot upgrade/install. Invalid status:"
	$HELM_STATUS_CMD
	exit 1
fi
