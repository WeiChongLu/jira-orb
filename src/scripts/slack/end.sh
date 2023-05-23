# define constant
SLACK_PATH=$(circleci env subst "${!PARAM_SLACK_PATH}")
GITHUB_ORGANIZATION=$(circleci env subst "${PARAM_GITHUB_ORGANIZATION}")
JIRA_ORGANIZATION=$(circleci env subst "${PARAM_JIRA_ORGANIZATION}")

# find basic variables
REPO_NAME=$(git config --get remote.origin.url |  sed 's#.*/\([^.]*\)\.git#\1#')
COMMIT_ID=$(git rev-parse --short HEAD)
CURR_TAG=$(git describe --exact-match --all HEAD)

# determine environment
ENVIRONMENT='DEV'
TAG_ENV_KEY='staging-v'
if echo $CURR_TAG | grep -q "prod-v"; then
  ENVIRONMENT='PROD'
  TAG_ENV_KEY='prod-v'
elif echo $CURR_TAG | grep -q "staging-v"; then
  ENVIRONMENT='STAGING'
  TAG_ENV_KEY='staging-v'
else 
  ENVIRONMENT='DEV'
  TAG_ENV_KEY='staging-v'
fi

# find branches between previous deployment and now
TAG_COMMIT_ID=$(git rev-list -n 1 $(git tag --sort=-creatordate | grep $TAG_ENV_KEY | awk 'NR==2{print $0}'))
BRANCHES=$(git log --merges --pretty=format:'%s' --first-parent $TAG_COMMIT_ID..master)

# parse each branch
IFS=$'\n'
DETAIL=$(echo "$BRANCHES" | while read LINE; do
  PR=$(echo $LINE | sed -n 's/[^#]*#\([0-9]*\).*/\1/p')
  BRANCH=$(echo $LINE | sed -n 's#.*/\([^/]*\)$#\1#p')
  BRANCH=$(echo "$BRANCH" | sed 's/#//g')
  JIRA=$(echo $BRANCH | grep -oE '[A-Z]{2,30}-[0-9]+')
  if [ "${#PR}" -eq 0 ]; then
    PR_STR=""
  else
    PR_LINK=$(echo "https://github.com/$GITHUB_ORGANIZATION/$REPO_NAME/pull/$PR")
    PR_STR=$(echo " [<$PR_LINK|#$PR>]")
    if [ -n "$JIRA" ]; then
      BRANCH_STR="<https://$JIRA_ORGANIZATION.atlassian.net/browse/$JIRA|$BRANCH>"
    else
      BRANCH_STR=$BRANCH
    fi
  fi
  echo "\n •${PR_STR} Branch: ${BRANCH_STR}"
done)

# send message
MESSAGE="{'text':'[*$REPO_NAME*] :white_check_mark: *$ENVIRONMENT* is now running \`$COMMIT_ID\` with $DETAIL'}"
curl -X POST -H 'Content-type: application/json' --data "$MESSAGE" $SLACK_PATH
