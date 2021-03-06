#!/bin/sh
#---------------------------------------------------------------------
#  _
# |_||aphaël
# | \\oy
# Git repo: https://github.com/rafutek
#
# Script to download music from YouTube, SoundCloud and other websites.
#---------------------------------------------------------------------

#---------------------------------------------------------------------
# Variables 
#---------------------------------------------------------------------
lang="fr"
artist=""
album=""
genre=""
year=""
cover=""
dest_directory=""
all_expressions=""
extract_artist=false
set_artist=false
set_cover=false
extract_cover=false
scriptname="$(basename "${0}" | sed "s/.sh$//")"
tempdir="temp"

#---------------------------------------------------------------------
# Functions
#---------------------------------------------------------------------

# Print the parameter as an error
# and quit with error code
error() {
	echo "${1}" >&2
	exit 1
}

# Get Ctrl+C event to kill the script
trap 'error' INT

# Print an error saying that parameter is required
# and quit with error code
required() {
    error "'${1}' is required. Please run installer script."
}

# Print usage and options to use
help_msg() {
    usage_msg
    echo "
OPTIONS:
	-h
            Print this help message and exit

        -l LANG
            Set the language for unknown artist and album,
            used for the folder hierarchy.
            For example:
            ${scriptname} -l en -a \"Brassens\" URL
                -> English, artist is Brassens and album is unknown
                    so folder hierarchy will be Brassens/Unknown/
            ${scriptname} -l fr -A \"Super album\" URL
                -> French, artist is unknown and album is Super album
                    so folder hierarchy will be Inconnu/Super album/

	-i PATH
            Set the absolute path to the cover image (not compatible with -I)

	-I
            Extract the image from the website (not compatible with -i)

	-e
            Extract the artist name from the title. To use when
            title has the pattern \"artist - title\". If the pattern
            is not present, artist is set to unknown or to the value
            given by the -a option.

	-a \"Artist\"
            Set the artist name for folder hierarchy and metadata

	-A \"Album\"
            Set the album name for folder hierarchy and metadata

	-g \"Genre\"
            Set the genre name for metadata

	-y XXXX
            Set the year for metadata

	-d DIR
            Set the absolute path to the destination directory

	-r \"exp1/exp2/[...]/expN\"
            Remove expression(s) in the music title. Expression \" - \"
            is removed by default.
    "
}

# Print script usage
usage_msg() {
    echo "
USAGE: 
    ${scriptname} [OPTIONS] URL

DESCRIPTION: 
    mdl is a utility to download music from the web,
    store it where you want in a nice folder hierarchy,
    and add some metadata to the downloaded mp3 file(s)."
}

# Error function: print usage and exit
exit_abnormal(){
    error "$(usage_msg)" 
}

# Error function: to call when options are not compatible 
# arguments: options
sim_call() {
    printf "Options "
    i=0
    max=$(( ${#} - 1 ))
    for arg in "${@}"
    do
	    case ${i} in
		    0)      sep="";;
		    ${max}) sep=" and ";;
		    *)      sep=", ";;
	    esac
	    printf "%s" "${sep}${arg}"
	    i=$((i+1))
    done
    error " are not callable simultaneously"
}

# Set initial variables values
set_variables() {
    [ "${dest_directory}" = "" ] && dest_directory="$(pwd)"
    set_language
    [ "${album}" = "" ] && album="${unknown}"
    [ "${genre}" = "" ] && genre="${unknown}"
    [ "${year}" = "" ] && year="0000"
    [ "${artist}" = "" ] && artist="${unknown}" # overwritten by artist extraction if there is
    [ "${set_artist}" = true ] && artist_opt="${artist}"
}

# Set "unknown" variable depending on language
set_language() {
    case "${lang}" in
        "fr")   unknown="Inconnu";;
        *)   unknown="Unknown";;
    esac
}

# Go to the wanted directory if not already there
goto() {
    [ "$(basename "$(pwd)")" = "$(basename "${1}")" ] ||
        [ -d "${1}" ] && cd "${1}" || return 1
}

# Create temporary directory if not already created
create_tempdir() {
    actualdir="$(pwd)"
    goto "${dest_directory}" && [ ! -d "${tempdir}" ] && 
        mkdir "${tempdir}" && cd "${actualdir}" || return 1
}

# Delete temporary directory if present
del_tempdir() {
    actualdir="$(pwd)"
    goto "${dest_directory}" && [ -d "${tempdir}" ] && rm -r "${tempdir}" || return 1
    if [ ! "$(basename "${actualdir}")" = "${tempdir}" ]; then
       cd "${actualdir}" || return 1
    fi
}

# Download music as mp3
download() { 
    actualdir="$(pwd)"
    goto "${tempdir}" || return 1
    
    echo "" && echo "Start downloading music from url..."
    opt=""
    [ "${cover}" = "extract-from-web" ] && opt=--embed-thumbnail
    youtube-dl -i -x --audio-format mp3 ${opt} "${URL}" -o "%(title)s.%(ext)s" &&
       cd "${actualdir}" || return 1
}

# Take every mp3 file in temporary directory,
# remove unwanted expressions, get music info,
# rename, add cover and metadata to the files and
# put them in their folder hierarchy
manage_tempfiles() {
    actualdir="$(pwd)"
    goto "${tempdir}" && ls ./*.mp3* > /dev/null || return 1
    
    music_number=1
    for filename in *".mp3"; do
        actual_filename="${filename}"
        remove_expressions &&
            extract_artist &&
            extract_title &&
            clear_filename &&
            rename_file &&
            add_cover &&
            add_metadata &&
            move_file || return 1
        music_number=$((music_number+1))
    done
    cd "${actualdir}" || return 1
}

# Remove unwanteed expressions from music filename
remove_expressions() {
    expressions="${all_expressions}"
    if [ "${expressions}" != "" ]; then
        [ -z "${filename}" ] && return 1 # variable filename must be non-zero
        newname="${filename}"
        iterate=true

        while [ ${iterate} = true ]; do
            # Iterate while expressions string contains a / character
            echo "${expressions}" | grep / > /dev/null || iterate=false
            
            # Get expression before the / character
            exp=${expressions##*/}

            # Keep the expressions after the / character
	    expressions=${expressions%/*}

            # Remove the expression from the filename
            [ ${#exp} -gt 0 ] && 
                newname="$(echo "${newname}" | sed "s/${exp}//gI")"
        done
        filename="${newname}"
    fi
}

# Extract artist from the title if needed
extract_artist() {
    if [ ${extract_artist} = true ]; then
        [ -z "${filename}" ] && return 1 # variable filename must be non-zero
        if echo "${filename}" | grep -q " - "; then
            artist=${filename%% - *}
            filename="$(echo "${filename}" | sed "s/${artist}//")"
        else
            # no artist to extract
            [ "${set_artist}" = false ] && artist="${unknown}"
            [ "${set_artist}" = true ] && artist="${artist_opt}"
        fi
    fi
    return 0
}

extract_title() {
    [ -z "${filename}" ] && return 1 # variable filename must be non-zero
    # Remove artist separator, spaces before and after the title and file extension
    title="$(echo "${filename}" | sed "s/\s-\s//; s/\s*\<//; s/\s*$//; s/.mp3$//")"
    filename="${title}.mp3"
    return 0
}

# Remove uneeded characters
clear_filename() {
    [ -z "${filename}" ] && return 1 # variable filename must be non-zero
    
    # Remove separator - and spaces before and after the filename
    noext="$(echo "${filename}" | sed "s/.mp3//")"
    filename="$(echo "${noext}" | sed "s/\s//g").mp3"
    return 0
}

rename_file() {
    # The actual file must be present and its new name non-zero
    [ -f "${actual_filename}" ] && [ -z "${filename}" ] && return 1
    if [ ! "${actual_filename}" = "${filename}" ]; then
        mv "${actual_filename}" "${filename}" || return 1
    fi
    return 0
}

add_cover() {
    [ -f "${filename}" ] || return 1 # filename must be present
    if [ "${set_cover}" = true ]; then
        [ -n "${cover}" ] && temp_file="_${filename}" &&
            ffmpeg -hide_banner -i "${filename}" -i "${cover}" \
            -map 0 -c:a copy -map 1 -c:v copy "${temp_file}" &&
            rm "${filename}" && mv "${temp_file}" "${filename}" || return 1
    fi
    return 0
}

# Add album, artist, year, genre and image if wanted
add_metadata() {
    [ -f "${filename}" ] &&
        mid3v2 -T "${music_number}" -t "${title}" -a "${artist}"\
        -A "${album}" -g "${genre}" -y ${year} "${filename}" &&
        echo "Added metadata to ${filename}:" &&
        echo "  num: ${music_number}" &&
        echo "  title: ${title}" &&
        echo "  artist: ${artist}" &&
        echo "  album: ${album}" &&
        echo "  genre: ${genre}" &&
        echo "  year: ${year}" || return 1
}

# Place file in appropriate directory
move_file() {
    actualdir="$(pwd)"
    goto "${dest_directory}" &&
        [ -f "${tempdir}/${filename}" ] &&
        hierarchy="${artist}/${album}" &&
        mkdir -p "${hierarchy}" &&
        mv -f "${tempdir}/${filename}" "${hierarchy}/${filename}" &&
        echo "Moved ${filename} to ${hierarchy}/" || return 1

    cd "${actualdir}" || return 1
}

#---------------------------------------------------------------------
# Script starts here
#---------------------------------------------------------------------

# Check required packages
command -v youtube-dl > /dev/null || required "youtube-dl"
command -v ffmpeg > /dev/null || required "ffmpeg"
command -v mid3v2 > /dev/null || required "mid3v2"

# Get different options
while getopts ":hl:ea:A:g:y:Ii:d:r:" opt; do
    case "${opt}" in
    h)  help_msg && exit 0;;
    l)  lang=${OPTARG};;
    e)  extract_artist=true;;
    a)  set_artist=true && artist=${OPTARG};;
    A)  album=${OPTARG};;
    g)  genre=${OPTARG};;
    y)  year=${OPTARG};;
    i)  if [ "${extract_cover}" = false ];then
            set_cover=true
        else
            sim_call "${opt}" "I"
        fi
        cover=${OPTARG};;
    I) if [ "${set_cover}" = false ];then
    	    extract_cover=true
        else
            sim_call "${opt}" "i"
        fi
        cover="extract-from-web";;
    d)  dest_directory=${OPTARG};;	
    r)  all_expressions=${OPTARG};;
    *)  exit_abnormal;;
    esac
done

# Check music url 
for URL in "$@"; do :; done
[ "${URL}" = "" ] && exit_abnormal

set_variables
del_tempdir 

create_tempdir && 
    download && 
    manage_tempfiles || echo "Runtime error" >&2

del_tempdir




