#!/bin/bash
clear


##########################################
####  START OF CHECKS AND VALIDATIONS ####
##########################################


# Check for debug flag
DEBUG=false

if [[ "$1" == "debug" ]]; then
    DEBUG=true
fi

# Source the helper functions
source ./helper_functions.sh

# Ensure the logs directory exists
mkdir -p "$COMMON_DIR"

# Check if gh CLI is installed and user is logged in
check_gh_installed
check_gh_logged_in

# Source the release version from the file
if [ -f $ENV_FILE ]; then
    source $ENV_FILE
else
    handle_error "Release version file not found. Please run the first script to set the release version."
fi

# Check if the release version is set in the environment variable
if [ -z "$RELEASE_VERSION" ]; then
    handle_error "Please set the release version environment variable (RELEASE_VERSION)."
fi

# Validate the release version format
if [[ ! "$RELEASE_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    handle_error "Invalid release version format. RELEASE_VERSION should be in the format vX.X.X (e.g., v1.0.0)."
fi


##########################################
#####     START OF RELEASE TAGS      #####
##########################################


echo -e "${GREEN}Release version is valid: $RELEASE_VERSION${NC}"

# # Log the release version
echo -e "\n||||||||||||||||||||||||||||||" >> $LOG_FILE
echo -e "Starting second phase of release process for version: $RELEASE_VERSION" >> $LOG_FILE
echo -e "||||||||||||||||||||||||||||||\n" >> $LOG_FILE


# Create a new release with auto-generated release notes
echo -e "\n${BLUE}Creating a new release with auto-generated release notes...${NC}"
run_command gh release create $RELEASE_VERSION --generate-notes
echo -e "${GREEN}Created a new release with auto-generated release notes${NC}"


# Get the latest commit hash
LATEST_TAG=$(git describe --tags `git rev-list --tags --max-count=1`)
LATEST_COMMIT_HASH=$(git rev-list -n 1 "$LATEST_TAG")

if [ $? -ne 0 ]; then
    handle_error "Failed to get the latest commit hash."
fi
echo -e "${GREEN}Saved latest commit ${NC}$LATEST_COMMIT_HASH ${GREEN}for release $LATEST_TAG to update kubernetes deployment.yaml"


##########################################
##### START OF KUBERNETES DEPLOYMENT #####
##########################################


# Find kubernetes manifests
kubernetes=$(find ~ -type d -name 'kubernetes-manifests' -print -quit)
if [ -z "$kubernetes" ]; then
    handle_error "Kubernetes manifests directory not found."
fi
echo "Found kubernetes manifests at $kubernetes"
cd $kubernetes

run_command git checkout master
run_command git pull
run_command git checkout -b cms-release-$RELEASE_VERSION
echo -e "${GREEN}Created a new release branch: ${NC}cms-release-$RELEASE_VERSION\n"

# Update deployment.yaml with the latest commit hash
run_command sed -i '' "s|image: registry\.uw\.systems/uwcouk-cms/uw\.co\.uk-cms-v2:[^ ]*|image: registry.uw.systems/uwcouk-cms/uw.co.uk-cms-v2:$LATEST_COMMIT_HASH|" prod-aws/uwcouk-cms/cms-v2/deployment.yaml
if [ $? -ne 0 ]; then
    handle_error "Failed to update deployment.yaml with latest commit hash."
fi
echo -e  "${GREEN}Updated deployment.yaml with latest commit hash:${NC} $LATEST_COMMIT_HASH\n"

# Commit the changes
run_command git add .
run_command git commit -m "Update CMS image to $LATEST_COMMIT_HASH"
echo -e "${GREEN}Committed the changes to the deployment.yaml${NC}\n"

# Push the changes
run_command git push --set-upstream origin cms-release-$RELEASE_VERSION
echo -e "${GREEN}Pushed the changes to the remote repository${NC}\n"

# Create PR
PR_URL=$(gh pr create --title "Release CMS $RELEASE_VERSION" --body "Automated release notes for $RELEASE_VERSION" --base "master" --head "cms-release-$RELEASE_VERSION")
if [ $? -ne 0 ]; then
    handle_error "Failed to create a pull request."
fi
echo -e "${GREEN}Created PR for release CMS $RELEASE_VERSION${NC}"
echo -e "${BLUE} just copy paste this to your team's slack channel${NC}"
echo -e "Pleasse help me out with an approval on this PR for DEPLOYING $RELEASE_VERSION\n\n $PR_URL\nThank you!\n"
echo -e "PR URL: $PR_URL" >> $LOG_FILE

echo -e "\n${YELLOW}Once it is approved, the new release will be deployed to production"
echo -e "${YELLOW}Hopefully it's not Friday, good luck!${NC}"