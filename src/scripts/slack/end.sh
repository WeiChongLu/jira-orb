GET_JIRA_INFO() {
JIRA_AUTH=$1
JIRA_ID=$2
JIRA_INFO_DATA=$(curl -X GET -H 'Content-type: application/json' -H "Authorization: Basic $JIRA_AUTH" "https://waylontest.atlassian.net/rest/api/3/issue/$JIRA_ID")
echo $JIRA_INFO_DATA
}

GET_JIRA_EPIC() {
IS_SUBTASK=true
JIRA_AUTH=$1
JIRA_ID=$2
EPIC_SUMMARY=""
while [ "$IS_SUBTASK" = true ]; do
  JIRA_INFO=$(GET_JIRA_INFO $JIRA_AUTH $JIRA_ID)
  IS_SUBTASK=$(echo $JIRA_INFO | jq -r '.fields.issuetype.subtask')
  if [ "$IS_SUBTASK" = true ]; then
    JIRA_ID=$(echo $JIRA_INFO | jq -r '.fields.parent.key')
  else
    IS_SUBTASK=false
    EPIC_SUMMARY=$(echo $JIRA_INFO | jq '.fields.parent.fields.summary')
  fi
done
echo $EPIC_SUMMARY
}

# define constant
SLACK_PATH=$(circleci env subst "${!PARAM_SLACK_PATH}")
JIRA_AUTH=$(circleci env subst "${!PARAM_JIRA_AUTH}")
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
BRANCHES=$(git log --pretty=format:'%s' --first-parent $TAG_COMMIT_ID..master)

# parse each branch
IFS=$'\n'
DETAIL=$(echo "$BRANCHES" | while read LINE; do
  PR=$(echo $LINE | sed -n 's/[^#]*#\([0-9]*\).*/\1/p')
  BRANCH=$(echo $LINE | sed -n 's#.*/\([^/]*\)$#\1#p')
  if [ -n "$BRANCH" ]; then 
    BRANCH=$(echo "$BRANCH" | sed 's/#//g')
    JIRA=$(echo $BRANCH | grep -oE '[A-Z]{2,30}-[0-9]+')
  else
    JIRA=$(echo $LINE | grep -oE '[A-Z]{2,30}-[0-9]+' | head -n 1)
    BRANCH=$JIRA
  fi
  if [ "${#PR}" -eq 0 ]; then
    PR_STR=""
  else
    PR_LINK=$(echo "https://github.com/$GITHUB_ORGANIZATION/$REPO_NAME/pull/$PR")
    PR_STR=$(echo " [<$PR_LINK|#$PR>]")
  fi
  if [ -n "$JIRA" ]; then
    BRANCH_STR="<https://$JIRA_ORGANIZATION.atlassian.net/browse/$JIRA|$BRANCH>"
    EPIC_SUMMARY=$(GET_JIRA_EPIC $JIRA_AUTH $JIRA)
    if [ -n "$EPIC_SUMMARY" ] && [ "$EPIC_SUMMARY" != "null" ]; then
      echo "\n •${PR_STR} Branch: ${BRANCH_STR} (Epic: $EPIC_SUMMARY)"
    else
      echo "\n •${PR_STR} Branch: ${BRANCH_STR}"
    fi
  fi 
done)

# send message
MESSAGE="{'text':'[*$REPO_NAME*] :white_check_mark: *$ENVIRONMENT* is now running \`$COMMIT_ID\` with $DETAIL'}"
curl -X POST -H 'Content-type: application/json' --data "$MESSAGE" $SLACK_PATH