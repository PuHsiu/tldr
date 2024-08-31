#!/bin/bash

# Check if required tools are installed
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed. Aborting."; exit 1; }

export FORCE_SPEACH_TO_TEXT=0
export INTERACTIVE_MODE=0
export SHOW_PROMPT=0
export PBCOPY=0

llm="./llm_adoptor/ollama.sh"

# TODO: update progress for each file
# mgmt a struct, and flush all each times.
# TODO: error handling when external call failed
# TODO: Read progress from external call and response on main terminal (ARG_MAX)

cleanup=()

update_progress() {
    _update_progress "$1" "$2" 1>&2
}

_update_progress(){
    local video_identifier="$1"
    local target_stage="$2"
    local progress=0
    local max_progress=5

    case "$target_stage" in 
        dw_subs)
            progress=1
            progress_txt="Downloading Subtitles/Video"
            ;;
        c_mp3)
            progress=2
            progress_txt="Converting Video to Audio"
            ;;
        stt)
            progress=3
            progress_txt="Converting Audio to Text"
            ;;
        summarize)
            progress=4
            progress_txt="Summarizing"
            ;;
        completed | *)
            progress=${max_progress}
            progress_txt="Almost done ...."
            ;;
    esac
    
    echo -ne "${video_identifier}: ["
    for i in `seq ${max_progress}`; do 
        if [ $i -le ${progress} ]; then
            echo -ne "####";
        else
            echo -ne "    ";
        fi
    done
    echo -ne "] ($((100 * ${progress} / ${max_progress}))%) ${progress_txt}                \r" 
}

debug(){
    echo $@ >&2
}

exitfn() {
    if [ "$1" != "done" ]; then
        exit 1
    fi

    for idx in ${!cleanup[@]}; do
        file=${cleanup[$idx]}

        if [ -f "$file" ]; then
            debug rm "$file"
        fi
    done;

    exit 0
}

interactive_mode(){
    local discussion=""
    local video_identifier="$1"
    local subtitle_name="$2"
    local subtitle_file="$3"
    local subtitle_content=$(cat "$subtitle_file")

    result=$($llm summarize_by_llm "$video_identifier" "$subtitle_name" "$subtitle_file")

    # update_progress "${video_identifier}" completed
    echo "總結：${result}"
    echo
    echo -e "\033[1;34m >>> 進入對話模式，輸入 \033[2mexit\033[0m\033[1;34m 離開，輸入 \033[2mreset\033[0m\033[1;34m 清除記憶，輸入 \033[0m\033[2msource\033[0m\033[1;34m 印出原始文件，輸入 \033[0m\033[2mmemory\033[0m\033[1;34m 印出討論全文"

    while true; do
        echo
        echo -ne "\033[1;32m > 你的提問： \033[0m"
        read user_input

        if [ "$user_input" = "exit" ]; then
            break
        elif [ "$user_input" = "reset" ]; then
            discussion=""
            continue
        elif [ "$user_input" = "source" ]; then
            echo "${subtitle_content}"
            continue
        elif [ "$user_input" = "memory" ]; then
            echo "${discussion}"
            continue
        fi

        result=$($llm discuss_with_llm "$video_identifier" "$subtitle_file")

        echo ""
        echo "${result}"

        discussion="${discussion}\nTopic: ${user_input}\nContent: ${result}"
    done
}

trap "exitfn" INT

video_urls=()

for i in "$@"; do
  case $i in
    # -e=*|--extension=*)
    #   EXTENSION="${i#*=}"
    #   shift # past argument=value
    #   ;;
    --force-stt)
      export FORCE_SPEACH_TO_TEXT=1
      ;;
    --interactive)
      export INTERACTIVE_MODE=1
      ;;
    http*)
      video_urls+=("$i")
      ;;
    --show-prompt)
      export SHOW_PROMPT=1
      ;;
    --pbcopy)
      export PBCOPY=1
      ;;
    *)
      ;;
  esac
done

# Main script
if [ "${#video_urls[@]}" = "0" ]; then
    echo -ne "\033[1;32m > Enter YouTube video URL: \033[0m"
    read video_url
    video_urls+=("$video_url")
fi

for idx in ${!video_urls[@]}; do
    video_url=${video_urls[$idx]}
    video_identifier="$(echo -n $video_url | sed -E 's/.*[?&]v=([^&]+).*/\1/')"

    subtitle_meta=$(./yt_subs_fetcher.sh fetch_subtitles "$video_identifier" "$video_url")
    echo -n "$subtitle_meta" >&2
    subtitle_name=$(echo -n "$subtitle_meta" | jq -r ".title")
    subtitle_file=$(echo -n "$subtitle_meta" | jq -r ".rename")

    if [ "$INTERACTIVE_MODE" = "1" ]; then
        interactive_mode "$video_identifier" "$subtitle_name" "$subtitle_file"
    elif [ "$PBCOPY" = "1" ]; then
        echo "Content prepared, press any key to pbcopy ... "
        read any
        cat ${subtitle_file} | grep "^[^0-9]" | pbcopy
    fi
done;

exitfn done