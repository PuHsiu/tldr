#!/bin/bash

source venv/bin/activate

llm_model=gemma2

# Check if required tools are installed
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed. Aborting."; exit 1; }
command -v ollama >/dev/null 2>&1 || { echo "ollama is required but not installed. Aborting."; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is required but not installed. Aborting."; exit 1; }
command -v whisper >/dev/null 2>&1 || { echo "whisper is required but not installed. Aborting."; exit 1; }

FORCE_SPEACH_TO_TEXT=0
INTERACTIVE_MODE=0

# TODO: update progress for each file
# mgmt a struct, and flush all each times.
# TODO: error handling when external call failed
# TODO: Read progress from external call and response on main terminal

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

generate_subtitles() {
    local video_file="$1"
    local output_file="$2"

    whisper --model small --output_format txt "${video_file}" 2>&1  > whisper.log
    echo "${output_file}"
}

summarize_by_llm() {
    local video_identifier="$1"
    local input_file="$2"
    local input_file_content=$(cat "$input_file")

    update_progress "${video_identifier}" summarize

    llm_prompt="
    '''
        ${input_file_content}
    '''
    Summarize the content above using traditional chinese, more focusing on ${input_file}
    "

    result=$(ollama run "${llm_model}" "${llm_prompt}")
    echo "$result"
}

# Function to convert video to mp3 using ffmpeg
convert_to_mp3() {
    local input_file="$1"
    local output_file="$2"
    
    ffmpeg -i "$input_file" -vn -acodec libmp3lame -q:a 2 "$output_file" 2>&1 > ffmpeg.log
    
    echo "$output_file"
}

exitfn() {
    if [ "${subtitle_file}" != "" ] && [ -f "${subtitle_file}" ]; then
        echo rm "${subtitle_file}"
    fi

    if [ "${video_file}" != "" ] && [ -f "${video_file}" ]; then
        echo rm "${video_file}"
    fi

    if [ "${mp3_file}" != "" ] && [ -f "${mp3_file}" ]; then 
        echo rm "${mp3_file}"
    fi

    exit
}

interactive_mode(){
    local discussion=""
    local video_identifier="$1"
    local subtitle_file="$2"
    local subtitle_content=$(cat "$subtitle_file")

    result=$(summarize_by_llm "$video_identifier" "$subtitle_file")

    update_progress "${video_identifier}" completed
    echo "總結：${result}"
    echo
    echo -e "\033[1;34m >>> 進入對話模式，輸入 \033[2mexit\033[0m\033[1;34m 離開，輸入 \033[2mreset\033[0m\033[1;34m 清除記憶，輸入 \033[0m\033[2msource\033[0m\033[1;34m 印出原始文件"

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
        fi

        llm_prompt="
        source: '''
        echo ${subtitle_content}
        '''
        discussion: '''
        echo ${discussion}
        '''
        Based on source and discussion above, please answer the question in traditional chinese: ${user_input}
        "
        
        result=$(ollama run "${llm_model}" "${llm_prompt}")

        echo ""
        echo "${result}"

        discussion="${discussion}\nTopic: ${user_input}\nContent: ${result}"
    done
}

fetch_subtitles(){
    local video_identifier="$1"
    local video_url="$2"

    # Download subtitles or video
    update_progress "${video_identifier}" dw_subs
    yt_dlp_output=$(./yt-dlp --write-subs --skip-download "$video_url" 2>&1)

    if [ "$FORCE_SPEACH_TO_TEXT" = "0" ] && $(echo "$yt_dlp_output" | grep -q "Writing video subtitles"); then
        subtitle_file=$(echo "$yt_dlp_output" | grep "Writing video subtitles" | head -1 | awk -F': ' '{print $NF}')
    else
        video_file=$(./yt-dlp -j --no-simulate -o "out.%(ext)s" "${video_url}"  | jq -r '.filename')
        mp3_file=${video_file%.*}.mp3
        subtitle_file=${mp3_file%.*}.txt

        # Convert video to mp3
        update_progress "${video_identifier}" c_mp3
        convert_to_mp3 "$video_file" "${mp3_file}"

        update_progress "${video_identifier}" stt
        generate_subtitles "$mp3_file" "$subtitle_file"
    fi

    subtitle_content=$(cat "${subtitle_file}")

    llm_prompt="
    '''
    Title: ${subtitle_file}
    Content: ${subtitle_content}
    '''
    Given a new file name for content above within 5~30 words in traditional chinese.
    To make response parsing easily, do not provide any noise like symbol or syntax highlight  in response
    "

    rename=$(ollama run "${llm_model}" "${llm_prompt}")
    ext=$(echo "$filename" | sed -E 's/.*\[(.*)\](.*)/[\1]\2/')

    mv "$subtitle_file" "$rename$ext"

    echo "$rename"
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
      FORCE_SPEACH_TO_TEXT=1
      ;;
    --interactive)
      INTERACTIVE_MODE=1
      ;;
    http*)
      video_urls+=("$i")
      ;;
    *)
      ;;
  esac
done

# Main script
if [ "${#video_urls[@]}" = "0" ]; then
    echo -ne "\033[1;32m > Enter YouTube video URL: \033[0m"
    read video_url
fi

for idx in ${!video_urls[@]}; do
    video_url=${video_urls[$idx]}
    video_identifier="$video_url"

    subtitle_file=$(fetch_subtitles "$video_identifier" "$video_url")

    if [ "$INTERACTIVE_MODE" = "1" ]; then
        interactive_mode "$video_identifier" "$subtitle_file"
    fi
done;

exitfn
