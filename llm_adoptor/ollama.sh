#!/bin/bash

# Check if required tools are installed
command -v ollama >/dev/null 2>&1 || { echo "ollama is required but not installed. Aborting."; exit 1; }

llm_model=gemma2:2b

show_prompt() {
    if [ "${SHOW_PROMPT}" = "0" ]; then
      return 0
    fi

    local prompt="$1"
    echo "${prompt}" 1>&2
}

exitfn() {
    if [ "$1" != "done" ]; then
        exit 1
    fi

    exit 0
}

trap "exitfn" INT

summarize_by_llm() {
    local video_identifier="$1"
    local subtitle_name="$2"
    local input_file="$3"
    local input_file_content=$(cat "$input_file")

    # update_progress "${video_identifier}" summarize

    llm_prompt="
    '''
        ${input_file_content}
    '''
    Summarize the content above using traditional chinese, more focusing on ${subtitle_name}
    "

    show_prompt "$llm_prompt"

    result=$(ollama run "${llm_model}" "${llm_prompt}")
    echo "$result"
}

discuss_with_llm() {
    local discussion=""
    local video_identifier="$1"
    local subtitle_file="$2"
    local subtitle_content=$(cat "$subtitle_file")

    llm_prompt="
    source: '''
    ${subtitle_content}
    '''
    discussion: '''
    ${discussion}
    '''
    Based on source and discussion above, please answer the question in traditional chinese: ${user_input}
    "

    result=$(ollama run "${llm_model}" "${llm_prompt}")
    echo "$result"
}

${1} "${@:2}"

exitfn done