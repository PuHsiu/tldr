command -v dialog >/dev/null 2>&1 || { brew install dialog; }

source ./config.sh

prepare_whisper() {
    if [ ! -d venv ]; then
        python3 -m venv venv
    fi

    source venv/bin/activate
    command -v whisper >/dev/null 2>&1 || { pip3 install git+https://github.com/openai/whisper.git; }
    deactivate
}

prepare_ffmpeg() {
    command -v ffmpeg >/dev/null 2>&1 || { brew install ffmpeg; }
}

prepare_yt_dlp() {
    if [ ! -f yt-dlp ]; then
        curl -L -o yt-dlp 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos'
        chmod a+x ./yt-dlp
    fi
}

prepare_ffmpeg
prepare_whisper
prepare_yt_dlp

dialog_output=""

config_layer1_menu(){
    exec 3>&1

    dialog_output=$(
        dialog --clear --no-cancel --title "Menu" --menu "Chooseg" 20 50 2 \
        1 "Boost Options" \
        2 "LLM Adoptor" \
        3 "LLM Model" \
        Exit "Exit" \
    2>&1 1>&3)

    exec 3>&-
}

config_boost_options(){
    config_val_boost_whisper=$(get_config "${config_key_boost_whisper}" "0")

    exec 3>&1

    input=$(
        dialog --clear --no-cancel --checklist "Options" 10 50 50 \
            1 "Boost Whisper" $( [ "$config_val_boost_whisper" = "1" ] &&  echo 'on' || echo 'off' ) \
    2>&1 1>&3)

    exec 3>&-

    set_config "$config_key_boost_whisper" "$input"
}

config_llm_adoptor() {
    config_val_llm_adoptor=$(get_config "${config_key_llm_adoptor}" "ollama")

    exec 3>&1

    input=$(
        dialog --clear --no-cancel --title "" --radiolist "Adoptor: " 17 70 1 \
            "ollama" "ollama" $( [ "$config_val_llm_adoptor" = "ollama" ] && echo 'on' || echo 'off' )\
    2>&1 1>&3)

    exec 3>&-

    set_config "$config_key_llm_adoptor" "$input"
}

config_llm_model() {
    config_val_llm_model=$(get_config "${config_key_llm_model}" "gemma2:2b")

    exec 3>&1

    input=$(
        dialog --clear --no-cancel --title "" --form "" 20 50 0 \
            "LLM Model" 1 3 "$config_val_llm_model" 1 14 10 0 \
    2>&1 1>&3)

    exec 3>&-

    set_config "$config_key_llm_model" "$input"
}

route_config() {
    while true; do
        config_layer1_menu

        case "$dialog_output" in
        1 ) 
            config_boost_options
        ;;
        2 )
            config_llm_adoptor
        ;;
        3 ) 
            config_llm_model
        ;;
        Exit )
            exit 0
        ;;
        esac
    done
}

route_config

find . -name "*.sh" -exec chmod a+x {} \;