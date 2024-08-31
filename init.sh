
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

find . -name "*.sh" -exec chmod a+x {} \;