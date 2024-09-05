#!/bin/bash

export config_key_llm_adoptor=".llm_adoptor"
export config_key_boost_whisper=".boost .whisper"
export config_key_llm_model=".llm_model"

CONFIG_FILE="./.config.json"
DEFAULT_CONFIG_FILE="./config.default.json"

get_config(){
    key="$1"
    default_val="$(jq -r \'$key\' \"$DEFAULT_CONFIG_FILE\")"
    jq -r "$key // \"${default_val}\"" "$CONFIG_FILE"
}

set_config(){
    key="$1"
    val="$2"

    if [ ! -f "${CONFIG_FILE}" ] || [ "" = $(cat "$CONFIG_FILE")]; then
        cp "$DEFAULT_CONFIG_FILE" "$CONFIG_FILE"
    fi

    jq "${key} = \"${val}\""<<<$(cat "$CONFIG_FILE") > "$CONFIG_FILE"
}
