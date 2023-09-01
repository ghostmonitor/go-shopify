#!/bin/bash
AWS_ECR_REGISTRY_ID="${AWS_ECR_REGISTRY_ID:?AWS_ECR_REGISTRY_ID env var is required}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
DOCKERFILE=${DOCKERFILE:-Dockerfile*}
PATTERN='recart/\([a-z]\+\):\([0-9\.]\+\)\([-a-z]\+\)\?'
COMMIT_MSG_FILE=".GH_COMMIT_MSG"
BRANCH_FILE=".GH_BRANCH"
RECART_GH_USER="${RECART_GH_USER:-recart-platform-internal}"
RECART_GH_EMAIL="${RECART_GH_EMAIL:-ops@recart.com}"
set -e

echo "Update base images in every Dockerfile" > "${COMMIT_MSG_FILE}"
echo >> "${COMMIT_MSG_FILE}"

find . -name "${DOCKERFILE}" -not -path "./node_modules/*" -not -path "./.*" -exec grep "${PATTERN}" {} \+ | while read -r gline
do

	DOCKERFILE=$(echo "${gline}" | cut -d':' -f1)
	line=$(echo "${gline}" | cut -d':' -f2-)
	# grep for 'recart/$IMAGE_TYPE:$IMAGE_VERSION[-$IMAGE_VERSION_SUFFIX]'
	# Example: recart/typescript:18-onbuild
	img=$(echo "${line}" | grep -o "${PATTERN}")
	echo "Looking for new image for ${img}"
	name=$(echo "${img}" | cut -d':' -f1)
	tag=$(echo "${img}" | cut -d':' -f2)
	version=$(echo "${tag}" | cut -d'-' -f1)
	mainVersion=$(echo "${version}" | cut -d'.' -f1)
	suffix=$(echo "${tag}" | cut -s -d'-' -f2)

	if [ ! -f "base-images-${mainVersion}.json" ]; then
		aws ecr describe-images --repository-name "${name}" --output json --filter tagStatus=TAGGED --query "reverse(sort_by(imageDetails,& imagePushedAt))[*] | [?imageTags[?starts_with(@,'$mainVersion')]]" > "base-images-${mainVersion}.json"
	fi

	if [ "${suffix}" = "" ]; then
		latest=$(jq -r "[.[] | select(.imageTags[] | startswith(\"${mainVersion}.\")) | select(.imageTags[] | contains(\"-\") | not)][0].imageTags[0] " < "base-images-${mainVersion}.json")
	else
		latest=$(jq -r "[.[] | select(.imageTags[] | startswith(\"${mainVersion}\")) | select(.imageTags[] | endswith(\"${suffix}\"))][0].imageTags[0]" < "base-images-${mainVersion}.json")
	fi

	echo "Latest is ${latest}"
	if [ "${latest}" = "${tag}" ]; then
		echo Skipping
	else
		latestLine="${line//:$tag/:$latest}"

		if [ ! -f "${BRANCH_FILE}" ]; then
			echo "platform/master/update-dockerfiles-${tag}-to-${latest}" > "${BRANCH_FILE}"
		fi

		echo "Update ${img} to ${latest} in ${DOCKERFILE}" >> "${COMMIT_MSG_FILE}"
		
		sed -i.bak "s#^${line}\$#${latestLine}#" "${DOCKERFILE}" && rm -f "${DOCKERFILE}.bak"
	fi

done

# Create a PR on GitHub if there are changes
if [[ "${CI}" = "true" ]] && [[ $(git status --porcelain --untracked-files=no | wc -l) -gt 0 ]]; then
	# Setup github
	sudo apt install -y gh ca-certificates
	echo "${RECART_GH_TOKEN}" | gh auth login --with-token
	gh auth setup-git

	GH_BRANCH=$(cat "${BRANCH_FILE}")
	git config --global user.name "${RECART_GH_USER}"
	git config --global user.email "${RECART_GH_EMAIL}"
	git checkout -b "${GH_BRANCH}"
	git commit -a -F "${COMMIT_MSG_FILE}"
	git remote set-url origin "https://${RECART_GH_TOKEN}@github.com/${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}.git"
	if [[ $(git branch --remotes --list "*${GH_BRANCH}") = "" ]]; then
		git push --set-upstream origin "${GH_BRANCH}"
		gh pr create --fill --head "${GH_BRANCH}"
	else
		git branch --set-upstream-to="origin/${GH_BRANCH}" "${GH_BRANCH}"
		git pull --rebase
		git push origin "${GH_BRANCH}"
	fi
fi

# Cleanup
rm -f "${BRANCH_FILE}" "${COMMIT_MSG_FILE}" base-images-*.json
