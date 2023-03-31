#!/usr/bin/env zsh

# Source the jira.sh script to access its functions
source ./jira.sh

_jira_autocomplete() {
    local -a completions
    local -a completions_with_descriptions
    local -a response
    completions=("${(@f)$(choose_task_and_create_branch "$1" --completion)}")
    completions_with_descriptions=("${(@f)$(choose_task_and_create_branch "$1" --completion-with-description)}")
    response=()

    for key in "${completions[@]}"; do
        response+=("${key}:${(k)completions_with_descriptions[(ie)$key]}")
    done

    _describe -t common-commands 'task key' response
}

compdef _jira_autocomplete jira.sh
