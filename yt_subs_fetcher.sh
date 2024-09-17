#!/bin/bash

source venv/bin/activate

# Check if required tools are installed
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed. Aborting."; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is required but not installed. Aborting."; exit 1; }
command -v whisper >/dev/null 2>&1 || { echo "whisper is required but not installed. Aborting."; exit 1; }

source ./config.sh

cleanup=(whisper-$$.log ffmpeg-$$.log)

exitfn() {
    deactivate

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

trap "exitfn" INT

debug(){
    echo $@ >&2
}

generate_subtitles() {
    local video_file="$1"
    local output_file="$2"
    local boost=$( [ "$BOOST" = "" ] && get_config "${config_key_boost_whisper}" || echo "$BOOST" )

    if [ "$boost" = "1" ]; then
        local boost_opt="--best_of 1 --beam_size 1"
    fi

    whisper --model small --output_format txt ${boost_opt} "${video_file}" > whisper-$$.log 2>&1
}

# Function to convert video to mp3 using ffmpeg
convert_to_mp3() {
    local input_file="$1"
    local output_file="$2"
    
    ffmpeg -y -i "$input_file" -vn -acodec libmp3lame -q:a 2 "$output_file" > ffmpeg-$$.log 2>&1
}

# FIXME: Video Stream like https://www.youtube.com/watch?v=OzxcVB40YXo will mis-download the chatroom record, not vidoe subtitles

fetch_subtitles(){
    local video_identifier="$1"
    local video_url="$2"

    # Download subtitles or video
    # update_progress "${video_identifier}" dw_subs
    yt_dlp_output=$(./yt-dlp --write-subs --skip-download "$video_url" 2>&1)

    if [ "$FORCE_SPEACH_TO_TEXT" = "0" ] && $(echo "$yt_dlp_output" | grep -q "Writing video subtitles"); then
        subtitle_file=$(echo "$yt_dlp_output" | grep "Writing video subtitles" | head -1 | awk -F': ' '{print $NF}')
    else
        video_file=$(./yt-dlp -j --no-simulate -o "%(title)s.%(ext)s" "${video_url}"  | jq -r '.filename')
        mp3_file=${video_file%.*}.mp3
        subtitle_file=${mp3_file%.*}.txt

        # Convert video to mp3
        # update_progress "${video_identifier}" c_mp3
        convert_to_mp3 "$video_file" "${mp3_file}"
        cleanup+=("$video_file")

        # update_progress "${video_identifier}" stt
        generate_subtitles "$mp3_file"
        cleanup+=("$mp3_file")
    fi

    rename="${video_identifier}.subs"
    mv "${subtitle_file}" "${rename}"

    jq --arg rename "${rename}" \
       --arg title "${subtitle_file}" \
       '$ARGS.named'<<<$(echo -n '{}')
}

${1} "${@:2}"

exitfn "done"