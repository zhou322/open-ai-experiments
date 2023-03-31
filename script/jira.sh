#!/bin/bash

# Configuration
JIRA_BASE_URL="https://your-jira-instance.atlassian.net"
JIRA_USERNAME="your-jira-username"
JIRA_API_TOKEN="your-jira-api-token"

CACHE_DIR="/tmp/jira_cache"
CACHE_EXPIRATION=$((60 * 5)) # Cache expires in 5 minutes (in seconds)

mkdir -p "$CACHE_DIR"

# Function to fetch a Jira board by its ID
get_board() {
  local board_id=$1
  curl -sS -X GET -H "Authorization: Basic $(echo -n "$JIRA_USERNAME:$JIRA_API_TOKEN" | base64)" \
    -H "Content-Type: application/json" \
    "$JIRA_BASE_URL/rest/agile/1.0/board/$board_id"
}

# Function to get active sprint ID by board ID
get_active_sprint_id() {
  local board_id=$1
  local response=$(curl -sS -X GET -H "Authorization: Basic $(echo -n "$JIRA_USERNAME:$JIRA_API_TOKEN" | base64)" \
    -H "Content-Type: application/json" \
    "$JIRA_BASE_URL/rest/agile/1.0/board/$board_id/sprint?state=active")
  echo "$response" | jq '.values[0].id'
}

# Function to list all tasks, issues, and bugs for a given Jira board ID in the active sprint
get_issues_by_board_id() {
  local board_id=$1
  local cache_file="$CACHE_DIR/board_${board_id}_issues.json"
  local current_time=$(date +%s)

  if [ -f "$cache_file" ] && [ $((current_time - $(find "$cache_file" -type f -exec stat -f "%m" {} \;))) -lt $CACHE_EXPIRATION ]; then
    cat "$cache_file"
  else
    local sprint_id=$(get_active_sprint_id "$board_id")
    local start_at=0
    local max_results=50
    local total=0
    local issues="[]"

    while true; do
      local response=$(curl -sS -X GET -H "Authorization: Basic $(echo -n "$JIRA_USERNAME:$JIRA_API_TOKEN" | base64)" \
        -H "Content-Type: application/json" \
        "$JIRA_BASE_URL/rest/agile/1.0/board/$board_id/sprint/$sprint_id/issue?startAt=$start_at&maxResults=$max_results")

      local new_issues=$(echo "$response" | jq '[.issues[] | {key: .key, summary: .fields.summary, issueType: .fields.issuetype.name}]')
      issues=$(echo "$issues" | jq ". + $new_issues")
      total=$(echo "$response" | jq '.total')

      start_at=$((start_at + max_results))
      if ((start_at >= total)); then
        break
      fi
    done

    echo "$issues" > "$cache_file"
    cat "$cache_file"
  fi
}

# Function to create a new Git branch with the Jira ticket ID
create_git_branch() {
  local jira_ticket_id=$1
  local branch_name="${jira_ticket_id}"

  git fetch --all
  git checkout master
  git pull origin master
  git checkout -b "$branch_name"
  git push -u origin "$branch_name"
}

# Function to choose a task and create a Git branch with the task ID
choose_task_and_create_branch() {
  local board_id completion_mode tasks_json tasks_count key summary tasks_array
  board_id=$1
  completion_mode="none"
  if [ "$2" == "--completion" ]; then
    completion_mode="keys"
  elif [ "$2" == "--completion-with-description" ]; then
    completion_mode="with-description"
  fi
  tasks_json=$(get_issues_by_board_id "$board_id")
  tasks_array=()

  tasks_count=$(echo "$tasks_json" | jq '. | length')
  for ((i = 0; i < tasks_count; i++)); do
    key=$(echo "$tasks_json" | jq -r ".[$i].key")
    summary=$(echo "$tasks_json" | jq -r ".[$i].summary")
    tasks_array+=("$key")
    if [ "$completion_mode" = "none" ]; then
      echo "$key - $summary"
    elif [ "$completion_mode" = "with-description" ]; then
      echo "$key"
      echo "$summary"
    fi
  done

  if [ "$completion_mode" = "keys" ]; then
    printf "%s\n" "${tasks_array[@]}"
  elif [ "$completion_mode" = "none" ]; then
    local selected_key
    while true; do
      read -p "Enter the task key: " selected_key
      if [[ " ${tasks_array[*]} " == *" $selected_key "* ]]; then
        break
      else
        echo "Invalid task key. Please enter a valid task key from the list."
      fi
    done

    create_git_branch "$selected_key"
  fi
}


board_id=285
board=$(get_board "$board_id")
echo "Board ID: $(echo "$board" | jq '.id'), Name: $(echo "$board" | jq '.name'), Type: $(echo "$board" | jq '.type')"

choose_task_and_create_branch "$board_id"
