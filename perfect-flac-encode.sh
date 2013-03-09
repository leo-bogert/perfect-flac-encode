#!/bin/bash
set -o nounset	# exit with error upon access of unset variable
set -o pipefail	# this is absolutely critical: make pipes exit with failure if any of the involved commands fails. the default is exit status of the last command.
#set -o errexit # see enable_errexit_and_errtrace() / main()
#set -o errtrace # see enable_errexit_and_errtrace() / main()
shopt -s nullglob # We use * for finding files but do no checking for the globbing pitfall which can happen if no files are found. See http://mywiki.wooledge.org/NullGlob
shopt -s failglob # Nullglob can have many side effects (see http://mywiki.wooledge.org/NullGlob) and we don't need any globs which return no files so it is a good idea to have this. I see that this seems to make the nullglob option redundant but I'd like to have them both: In case someone removes the failglob option because he needs failing globs, the nullglob will be needed so we can just already put it there.

################################################################################
# NAME: perfect-flac-encode
# WEBSITE: http://leo.bogert.de/perfect-flac-encode
# MANUAL: See Website.
#
# AUTHOR: Leo Bogert (http://leo.bogert.de)
# DONATIONS: bitcoin:1PZBKLBFnbBA5h1HdKF8PATk3JnAND91yp
# LICENSE:
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
# 
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.
################################################################################

################################################################################
# GLOBAL TODOs - please consider them before actually using the script!
################################################################################
# TODO: Review uses of command substitution $() and decide whether we should clone their stderr to the log file.
################################################################################

################################################################################
# Configuration:
################################################################################
# Those directories will be created in the output directory
# They MUST NOT contain further subdirectories because the shntool syntax does not allow it the way we use it
declare -A TEMP_DIRS # Attention: We have to explicitely declare the associative array or iteration over the keys will not work!
TEMP_DIRS[WAV_SINGLETRACK_SUBDIR]="Stage1_WAV_Singletracks_From_WAV_Image"
TEMP_DIRS[WAV_JOINTEST_SUBDIR]="Stage2_WAV_Image_Joined_From_WAV_Singletracks"
TEMP_DIRS[FLAC_SINGLETRACK_SUBDIR]="Stage3_FLAC_Singletracks_Encoded_From_WAV_Singletracks"
TEMP_DIRS[DECODED_WAV_SINGLETRACK_SUBDIR]="Stage4_WAV_Singletracks_Decoded_From_FLAC_Singletracks"

# Unit tests:
# Enabling these will damage the said files to test the checksum verification:
# If perfect-flac-encode exits with a "checksum failure" error then, the test succeeded.
# Notice that only enabling one at once makes sense because the script will terminate if ANY checksum verification fails :)
# Set to 1 to enable
declare -A UNIT_TESTS	# Attention: We have to explicitely declare the associative array or iteration over the keys will not work!
UNIT_TESTS["TEST_DAMAGE_TO_INPUT_WAV_IMAGE"]=0
UNIT_TESTS["TEST_DAMAGE_TO_SPLIT_WAV_SINGLETRACKS"]=0
UNIT_TESTS["TEST_DAMAGE_TO_REJOINED_WAV_IMAGE"]=0
UNIT_TESTS["TEST_DAMAGE_TO_FLAC_SINGLETRACKS"]=0
UNIT_TESTS["TEST_DAMAGE_TO_DECODED_FLAC_SINGLETRACKS"]=0
################################################################################
# End of configuration
################################################################################

################################################################################
# Global variables (naming convention: all globals are uppercase)
################################################################################
VERSION="BETA11"
FULL_VERSION=""			# Full version string which also contains the versions of the used helper programs.
INPUT_DIR_ABSOLUTE=""	# Directory where the input WAV/LOG/CUE can be found. Must not be written to by the script in any way.
OUTPUT_DIR_ABSOLUTE=""	# Directory where the output (FLACs/EAC LOG/PFE LOG/CUE/README.txt) is created. The temporary directories will be created here as well.
OUTPUT_OWN_LOG_ABSOLUTE=""	# Full path of the perfect-flac-encode log file. It must be a file in $OUTPUT_DIR_ABSOLUTE.
OUTPUT_SHA256_ABSOLUTE=""	# Full path of the output SHA256. It must be a file in $OUTPUT_DIR_ABSOLUTE
INPUT_CUE_LOG_WAV_BASENAME=""	# Filename of input WAV/LOG/CUE without extension. It must be a file in the directory $INPUT_DIR_ABSOLUTE.
INPUT_CUE_ABSOLUTE=""	# Full path of input CUE. It must be a file in the directory $INPUT_DIR_ABSOLUTE.
INPUT_LOG_ABSOLUTE=""	# Full path of input LOG. It must be a file in the directory $INPUT_DIR_ABSOLUTE.
INPUT_WAV_ABSOLUTE=""	# Full path of input WAV. It must be a file in the directory $INPUT_DIR_ABSOLUTE.

# Absolute paths to the temp directories. For documentation see above in the "Configuration" section.
# Must be subdirectories of the output directory, see ask_to_delete_existing_output_and_temp_dirs_or_die() for an explanation.
declare -A TEMP_DIRS_ABSOLUTE  # Attention: We have to explicitely declare the associative array or iteration over the keys will not work!
TEMP_DIRS_ABSOLUTE[WAV_SINGLETRACK_SUBDIR]=""
TEMP_DIRS_ABSOLUTE[WAV_JOINTEST_SUBDIR]=""
TEMP_DIRS_ABSOLUTE[FLAC_SINGLETRACK_SUBDIR]=""
TEMP_DIRS_ABSOLUTE[DECODED_WAV_SINGLETRACK_SUBDIR]=""
################################################################################
# End of global variables
################################################################################

log() {
	echo "$@" >> "$OUTPUT_OWN_LOG_ABSOLUTE"
}

stdout() {
	echo "$@" >&1
}

stderr() {
	echo "$@" >&2
}

log_and_stdout() {
	log "$@"
	stdout "$@"
}

log_and_stderr() {
	# log() won't work during early startup since the directory where the log file is located won't exist yet.
	# This can cause the call to log() to kill the script if we have errexit enabled.
	# So we should first do stderr() to ensure that the user gets the actual error message.
	stderr "ERROR: " "$@"
	log "ERROR: " "$@"
}

die() {
	log_and_stderr "$@"
	exit 1
}

# parameters: $1 = target working directory, absolute or relative to current working dir. if not specified, working directory is set to $OUTPUT_DIR_ABSOLUTE
set_working_directory_or_die() {
	#echo "Changing working directory to $dir..."
	if [ $# -eq 0 ] ; then
		local dir="$OUTPUT_DIR_ABSOLUTE" # We default to the output dir so the probability of accidentially damaging something is lower
	else
		local dir="$1"
	fi
	
	if ! cd "$dir" ; then
		die "Setting working directory failed!"
	fi
}

ask_to_delete_existing_output_and_temp_dirs_or_die() {
	# We only have to delete the output directory since the temp dirs will be subdirectories
	if [ ! -d "$OUTPUT_DIR_ABSOLUTE" ]; then
		return 0
	fi
	
	local confirmed=n
	read -p "The output directory exists already. Delete it and ALL contained files? (y/n)" confirmed
	
	if [ "$confirmed" == "y" ]; then
		rm --preserve-root -rf "$OUTPUT_DIR_ABSOLUTE"
	else
		die "Quitting because you want to keep the existing output."
	fi
}

delete_temp_dirs() {
	stdout "Deleting temp directories..."
	for tempdir in "${TEMP_DIRS_ABSOLUTE[@]}" ; do
		if [ ! -d "$tempdir" ]; then
			continue
		fi
		
		if ! rm --preserve-root -rf "$tempdir" ; then
			die "Deleting the temp files failed!"
		fi
	done
}

create_directories_or_die() {
	local output_dir_and_temp_dirs=( "$OUTPUT_DIR_ABSOLUTE" "${TEMP_DIRS_ABSOLUTE[@]}" )
	
	stdout "Creating output and temp directories..."
	for dir in "${output_dir_and_temp_dirs[@]}" ; do
		if [ -d "$dir" ]; then
			die "Dir exists already: $dir"
		fi
		
		if ! mkdir -p "$dir" ; then
			die "Making directory \"$dir\" in input directory failed!"
		fi
	done
}

create_log_file_or_die() {
	stdout "Logging to file: $OUTPUT_OWN_LOG_ABSOLUTE"

	if ! touch "$OUTPUT_OWN_LOG_ABSOLUTE" ; then
		die "Creating log file failed: $OUTPUT_OWN_LOG_ABSOLUTE"
	fi
}

check_whether_input_is_accurately_ripped_or_die() {
	log "Checking EAC LOG for whether AccurateRip reports a perfect rip..."
	
	if ! iconv --from-code utf-16 --to-code utf-8 "$INPUT_LOG_ABSOLUTE" | grep --quiet "All tracks accurately ripped" ; then
		die "AccurateRip reported that the disk was not ripped properly - aborting!"
	else
		log "AccurateRip reports a perfect rip."
	fi
}

# Uses "shntool len" to check for any of the following problems with the input WAV:
# - Data is not CD quality
# - Data is not cut on a sector boundary
# - Data is too short to be burned
# - Header is not canonical
# - Contains extra RIFF chunks
# - Contains an ID3v2 header
# - Audio data is not block‐aligned
# - Header is inconsistent about data size and/or file size
# - File is truncated
# - File has junk appended to it
check_shntool_wav_problem_diagnosis_or_die() {
	log "Using 'shntool len' to check the input WAV image for quality and file format problems..."
	
    #       length         expanded size                 cdr         WAVE        problems       fmt         ratio         filename
	#       54:04.55       572371004         B           ---         --          -----          wav         1.0000        Paul Weller - 1994 - Wild Wood.wav"
	# ^ \s*    \S*    \s*     \S*     \s*   \S*   \s*   (\S*)  \s*  (\S*)  \s*   (\S*)   \s*    \S*    \s*    \S*    \s*    (.*)$
	
	local regex="^\s*\S*\s*\S*\s*\S*\s*(\S*)\s*(\S*)\s*(\S*)\s*\S*\s*\S*\s*(.*)$"
	local len_output # defining & assigning it at once would overwrite $?
	
	if ! len_output="$(shntool len -c -t "$INPUT_WAV_ABSOLUTE" | grep -E "$regex")" ; then
		die "Regexp for getting the 'shntool len' output failed!"
	fi
	
	local cdr_column
	local wave_column
	local problems_column

	if ! cdr_column="$(echo "$len_output" | sed -r s/"$regex"/\\1/)" ; then
		die "Regexp for getting the 'shntool len' output failed!"
	fi

	if ! wave_column="$(echo "$len_output" | sed -r s/"$regex"/\\2/)" ; then
		die "Regexp for getting the 'shntool len' output failed!"
	fi

	if ! problems_column="$(echo "$len_output" | sed -r s/"$regex"/\\3/)" ; then
		die "Regexp for getting the 'shntool len' output failed!"
	fi
	
	if [ "$cdr_column" != "---" ] ; then
		die "CD-quality column of 'shntool len' indicates problems: $cdr_column"
	fi
	
	if [ "$wave_column" != "--" ] ; then
		die "WAVE column of 'shntool len' shows problems: $wave_column"
	fi
	
	if [ "$problems_column" != "-----" ] ; then
		die "Problems column of 'shntool len' shows problems: $problems_column"
	fi
}

# parameters:
# $1 = "test" or "copy" = which crc to get, EAC provides 2
get_eac_crc() {
	case "$1" in
		test)
			local mode="Test" ;;
		copy)
			local mode="Copy" ;;
		*)
			log_and_stderr "Invalid mode: $1"
			exit 1
	esac
	
	local regex="^([[:space:]]*)($mode CRC )([0-9A-F]*)([[:space:]]*)\$"
	iconv --from-code utf-16 --to-code utf-8 "$INPUT_LOG_ABSOLUTE" | grep -E "$regex" | sed -r s/"$regex"/\\3/
}

test_whether_the_two_eac_crcs_match_or_die() {
	# defining & assigning them at once would overwrite $?
	local test_crc
	local copy_crc

	if ! test_crc="$(get_eac_crc 'test')" ; then
		die "Getting the EAC Test CRC failed!"
	fi
	
	if ! copy_crc="$(get_eac_crc 'copy')" ; then
		die "Getting the EAC Copy CRC failed!"
	fi
	
	if [[ -z "$test_crc" || -z "$copy_crc" ]] ; then
		die "Test or copy CRC is empty!"
	fi
	
	log "Checking whether EAC Test CRC matches EAC Copy CRC..."
	if [ "$test_crc" != "$copy_crc" ] ; then
		die "EAC Test CRC does not match EAC Copy CRC!"
	fi
	log "Test and Copy CRC match."
}

test_eac_crc_or_die() {
	log "Comparing EAC CRC from EAC LOG to CRC of the input WAV image..."
	
	if [ ${UNIT_TESTS["TEST_DAMAGE_TO_INPUT_WAV_IMAGE"]} -eq 1 ]; then 
		log_and_stderr "Deliberately damaging the input WAV image (original is renamed to *.original) to test the EAC checksum verification ..."
		
		if ! mv --no-clobber "$INPUT_WAV_ABSOLUTE" "$INPUT_WAV_ABSOLUTE.original" ; then
			die "Renaming the original WAV image failed!"
		fi
		
		local input_wav_without_extension_absolute="$INPUT_DIR_ABSOLUTE/$INPUT_CUE_LOG_WAV_BASENAME"
		# We replace it with a silent WAV so we don't have to damage the original input image
		if ! shntool gen -l 1:23 -a "$input_wav_without_extension_absolute"; then 	# .wav must not be in -a
			die "Generating silent WAV file failed!"
		fi
	fi
	
	# defining & assigning them at once would overwrite $?
	local expected_crc
	local actual_crc
	
	if ! expected_crc="$(get_eac_crc 'copy')" ; then
		die "Getting the EAC CRC failed!"
	fi
	
	log "Computing EAC CRC of WAV image..."
	
	if ! actual_crc="$(eac-crc "$INPUT_WAV_ABSOLUTE")" ; then
		die "Computing EAC CRC of WAV image failed!"
	fi
	
	log "Expected EAC CRC: $expected_crc"
	log "Actual EAC CRC: $actual_crc"
	
	if [[ -z "$expected_crc" || -z "$actual_crc" ]] ; then
		die "Expected or actual CRC is empty!"
	fi
	
	if [ "$actual_crc" != "$expected_crc" ] ; then
		die "EAC CRC mismatch!"
	fi
	
	log "EAC CRC of input WAV image is OK."
}

split_wav_image_to_singletracks_or_die() {
	log "Splitting WAV image to singletrack WAVs..."
	
	# shntool syntax:
	# -q Suppress  non‐critical output (quiet mode).  Output that normally goes to stderr will not be displayed, other than errors or debugging information (if specified).
	# -d dir Specify output directory 
	# -f file Specifies a file from which to read split point data.  If not given, then split points are read from the terminal.
	# -m str Specifies  a  character  manipulation  string for filenames generated from CUE sheets.  
	# -n fmt Specifies the file count output format.  The default is %02d, which gives two‐digit zero‐padded numbers (01, 02, 03, ...).
	# -t fmt Name output files in user‐specified format based on CUE sheet fields. %t Track title, %n Track number
	# -- = indicates that everything following it is a filename
	
	# TODO: ask someone to proof read options. i did proof read them again already.
	# TODO: shntool generates a "00 - pregap.wav" for HTOA. Decide what to do about this and check MusicBrainz for what they prefer. Options are: Keep as track 0? Merge with track 1? Shift all tracks by 1?
	
	# Ideas behind parameter decisions:
	# - We use quiet mode because otherwise shntool will print the full paths of the input/output files and we don't want those in the log file
	# - We do NOT let shntool encode the FLAC files on its own. While testing it has shown that the error messages of FLAC are not printed. Further, because we want this script to be robust, we only use the core features of each tool and not use fancy stuff which they were not primarily designed for.
	# - We split the tracks into a subdirectory so when encoding the files we can just encode "*.wav", we don't need any mechanism for excluding the image WAV
	# - We replace Windows' reserved filename characters with "_". We do this because we recommend MusicBrainz Picard for tagging and it does the same. List of reserved characters was taken from http://msdn.microsoft.com/en-us/library/windows/desktop/aa365247%28v=vs.85%29.aspx
	# - We prefix the filename with the maximal amount of zeroes required to get proper sorting for the maximal possible trackcount on a CD which is 99. We do this because cuetag requires proper sort order of the input files and we just use "*.flac" for finding the input files
	
	if ! shntool split -q -d "${TEMP_DIRS_ABSOLUTE[WAV_SINGLETRACK_SUBDIR]}" -f "$INPUT_CUE_ABSOLUTE" -m '<_>_:_"_/_\_|_?_*_' -n %02d -t "%n - %t" -- "$INPUT_WAV_ABSOLUTE" ; then
		die "Splitting WAV image to singletracks failed!"
	fi
	
	if [ ${UNIT_TESTS["TEST_DAMAGE_TO_SPLIT_WAV_SINGLETRACKS"]} -eq 1 ]; then 
		log_and_stderr "Deliberately damaging a singletrack to test the AccurateRip checksum verification ..."
		
		local wav_singletracks=( "${TEMP_DIRS_ABSOLUTE[WAV_SINGLETRACK_SUBDIR]}"/*.wav )
		local first_track_without_extension_absolute

		if ! first_track_without_extension_absolute="${TEMP_DIRS_ABSOLUTE[WAV_SINGLETRACK_SUBDIR]}"/"$(basename "${wav_singletracks[0]}" ".wav")" ; then
			die "basename failed!"
		fi
		
		if ! rm --preserve-root -f "${wav_singletracks[0]}" ; then
			die "Removing the original WAV track 1 failed!"
		fi
		
		# accurateripchecksum will ignore trailing garbage in a WAV file and adding leading garbage would make it an invalid WAV which would cause the checksum computation to not even happen
		# Luckily, while reading the manpage of shntool I saw that it is able to generate silent WAV files. So we just replace it with a silent file as "damage":
		if ! shntool gen -l 1:23 -a "$first_track_without_extension_absolute"; then 	# .wav must not be in -a
			die "Generating silent WAV file failed!"
		fi
	fi
}

# parameters:
# $1 = tracknumber
# $2 = accuraterip version, 1 or 2
get_accuraterip_checksum_of_singletrack() {
	local tracknumber="$1"
	local accuraterip_version="$2"
	
	# remove leading zero (we use 2-digit tracknumbers)
	if ! tracknumber="$(echo "$tracknumber" | sed 's/^[0]//')" ; then 
		log_and_stderr "Invalid tracknumber: $1"
		return 1
	fi
	
	if [ "$accuraterip_version" != "1" -a "$accuraterip_version" != "2" ] ; then
		log_and_stderr "Invalid AccurateRip version: $accuraterip_version!"
		return 1
	fi
	
	local regex="^Track( {1,2})($tracknumber)( {2})accurately ripped \\(confidence ([[:digit:]]+)\\)  \\[([0-9A-Fa-f]+)\\]  \\(AR v$accuraterip_version\\)(.*)\$"
	
	iconv --from-code utf-16 --to-code utf-8 "$INPUT_LOG_ABSOLUTE" | grep -E "$regex" | sed -r s/"$regex"/\\5/
}

# parameters:
# $1 = filename with extension
get_tracknumber_of_singletrack() {
	local filename="$1"
	local regex='^([[:digit:]]{2}) - (.+)([.])(.+)$'
	
	echo "$filename" | grep -E "$regex" | sed -r s/"$regex"/\\1/
}

get_total_tracks_without_hiddentrack_from_cue() {
	cueprint -d '%N' "$INPUT_CUE_ABSOLUTE"
}

test_accuraterip_checksums_of_split_wav_singletracks_or_die() {
	log "Comparing AccurateRip checksums of split WAV singletracks to AccurateRip checksums from EAC LOG..."
	
	local inputdir_wav="${TEMP_DIRS_ABSOLUTE[WAV_SINGLETRACK_SUBDIR]}"
	local wav_singletracks=( "$inputdir_wav"/*.wav )
	local hidden_track="$inputdir_wav/00 - pregap.wav"
	local totaltracks

	if ! totaltracks="$(get_total_tracks_without_hiddentrack_from_cue)" ; then
		die "get_total_tracks_without_hiddentrack_from_cue failed!"
	fi
	
	if [ -f "$hidden_track" ] ; then
		log "Hidden track one audio found."
		local hidden_track_excluded_message=" (excluding hidden track)"
		
		# TODO: evaluate what musicbrainz says about joined hidden track vs hidden track as track0
		#shntool join "$inputdir_wav/00 - pregap.wav" "$inputdir_wav/01"*.wav
		#mv "joined.wav" "$inputdir_wav/01"*.wav
	else
		log "Hidden track one audio not found."
		local hidden_track_excluded_message=""
	fi
	
	local do_exit="0"
	log "Total tracks$hidden_track_excluded_message: $totaltracks"
	for filename in "${wav_singletracks[@]}"; do
		local filename_without_path
		
		if ! filename_without_path="$(basename "$filename")" ; then
			die "basename failed!"
		fi

		local tracknumber
		if ! tracknumber="$(get_tracknumber_of_singletrack "$filename_without_path")" ; then
			die "get_tracknumber_of_singletrack failed!"
		fi
		
		
		if  [ "$tracknumber" = "00" ] ; then
			log "Skipping tracknumber 0 as this is a hidden track, EAC won't list AccurateRip checksums of hidden track one audio"
			continue
 		fi
		
		local 'expected_checksums[1]'
		local 'expected_checksums[2]'
		
		if ! expected_checksums[1]="$(get_accuraterip_checksum_of_singletrack "$tracknumber" "1")" ; then
			expected_checksums[1]=""
			# No error handling because one of the two checksum queries will fail.
			# TODO: Instead have a get_accuraterip_checksum_version_of_singletrack to first find out which version checksum we are using. 
			# This will also allow us to set -o errexit
		fi

		if ! expected_checksums[2]="$(get_accuraterip_checksum_of_singletrack "$tracknumber" "2")" ; then
			expected_checksums[2]=""
			# No error handling because one of the two checksum queries will fail.
			# TODO: Instead have a get_accuraterip_checksum_version_of_singletrack to first find out which version checksum we are using. 
			# This will also allow us to set -o errexit
		fi
		
		if [ "${expected_checksums[2]}" != "" ] ; then
			local accuraterip_version="2"
		elif [ "${expected_checksums[1]}" != "" ] ; then
			local accuraterip_version="1"
		else
			die "AccurateRip checksum not found in LOG!"
		fi
		
		local expected_checksum="${expected_checksums[$accuraterip_version]^^}" # ^^ = convert to uppercase
		local actual_checksum
		
		if ! actual_checksum="$(accuraterip-checksum --accuraterip-v$accuraterip_version "$filename" "$tracknumber" "$totaltracks")" ; then
			die "accuraterip-checksum failed!"
		fi
		
		if [[ -z "$actual_checksum" || -z "$expected_checksum" ]] ; then
			die "actual_checksum or expected_checksum is empty!"
		fi
		
		if [ "$actual_checksum" != "$expected_checksum" ]; then
			log_and_stderr "AccurateRip checksum mismatch for track $tracknumber: expected='$expected_checksum'; actual='$actual_checksum'"
			local do_exit=1	# Don't exit right now so we get an overview of all checksums so we have a better chance of finding out what's wrong
		else
			log "AccurateRip checksum of track $tracknumber: $actual_checksum, expected $expected_checksum. OK."
		fi
	done
	
	if [ "$do_exit" = "1" ] ; then
		die "AccurateRip checksum mismatch for at least one track!"
	fi
}

# This genrates a .sha256 file with the SHA256-checksum of the original WAV image. We do not use the EAC CRC from the log because it is non-standard and does not cover the full WAV.
# Further, the sha256 will be part of the output directory: If the user ever needs to restore the original WAV image for restoring a physical copy of the CD, it can be used by perfect-flac-decode for checking whether decoding & re-joining the tracks worked properly.
generate_checksum_of_original_wav_image_or_die() {
	log "Generating checksum of original WAV image ..."

	local original_image_filename

	if ! original_image_filename="$(basename "$INPUT_WAV_ABSOLUTE")" ; then
		die "basename failed!"
	fi
	
	set_working_directory_or_die "$INPUT_DIR_ABSOLUTE" # We need to pass a relative filename to sha256 so the output does not contain the absolute path
	if ! sha256sum --binary "$original_image_filename" > "$OUTPUT_SHA256_ABSOLUTE" ; then
		die "Generating checksum of original WAV image failed!"
	fi
	set_working_directory_or_die
}

test_checksum_of_rejoined_wav_image_or_die() {
	log "Joining singletrack WAVs temporarily for comparing their checksum with the original image's checksum..."
	local original_image_checksum_file_absolute="$OUTPUT_SHA256_ABSOLUTE"
	local joined_image_absolute="${TEMP_DIRS_ABSOLUTE[WAV_JOINTEST_SUBDIR]}/joined.wav"

	# shntool syntax:
	# -q Suppress  non‐critical output (quiet mode).  Output that normally goes to stderr will not be displayed, other than errors or debugging information (if specified).
	# -d dir Specify output directory 
	# -- = indicates that everything following it is a filename
	
	# Ideas behind parameter decisions:
	# - We use quiet mode because otherwise shntool will print the full paths of the input/output files and we don't want those in the log file
	# - We join into a subdirectory because we don't need the joined file afterwards and we can just delete the subdir to get rid of it
	if ! shntool join -q -d "${TEMP_DIRS_ABSOLUTE[WAV_JOINTEST_SUBDIR]}" -- "${TEMP_DIRS_ABSOLUTE[WAV_SINGLETRACK_SUBDIR]}"/*.wav ; then 
		die "Joining WAV failed!"
	fi
	
	if [ ${UNIT_TESTS["TEST_DAMAGE_TO_REJOINED_WAV_IMAGE"]} -eq 1 ]; then 
		log_and_stderr "Deliberately damaging the joined image to test the checksum verification ..."
		echo "FAIL" >> "$joined_image_absolute"
	fi
	
	local -a original_sum
	# sha256sum will also print the filename so we split the output by spaces to an array and the first slot will be the actual checksum
	if ! read -r -a original_sum < "$original_image_checksum_file_absolute" ; then
		die "Reading the original image checksum file failed!"
	fi
	
	log "Computing checksum of joined WAV image..."
	local sha_output
	if ! sha_output="$(sha256sum --binary "$joined_image_absolute")" ; then
		die "sha256sum failed!"
	fi
	
	local -a joined_sum
	if ! read -r -a joined_sum <<< "$sha_output" ; then	# We cannot put $(sha256sum ..) into the input of <<< because the exit code will not hit the "if" then.
		die "Parsing sha256sum failed!"
	fi
	
	log $'Original checksum: \t\t' "${original_sum[0]}"
	log $'Checksum of joined image:\t' "${joined_sum[0]}"

	if [ -z "${original_sum[0]}" ] || [ -z "${joined_sum[0]}" ] ; then
		die "Checksum is empty!"
	fi
	
	if [ "${original_sum[0]}" != "${joined_sum[0]}" ]; then
		die "Checksum of joined image does not match original checksum!"
	fi
	
	log "Checksum of joined image OK."
}

encode_wav_singletracks_to_flac_or_die() {
	log "Encoding singletrack WAVs to FLAC ..."
	
	local inputdir="${TEMP_DIRS_ABSOLUTE[WAV_SINGLETRACK_SUBDIR]}"
	local outputdir="${TEMP_DIRS_ABSOLUTE[FLAC_SINGLETRACK_SUBDIR]}"
	
	# used flac parameters:
	# --silent	Silent mode (do not write runtime encode/decode statistics to stderr)
	# --warnings-as-errors	Treat all warnings as errors (which cause flac to terminate with a non-zero exit code).
	# --output-prefix=string	Prefix  each output file name with the given string.  This can be useful for encoding or decoding files to a different directory. 
	# --verify	Verify a correct encoding by decoding the output in parallel and comparing to the original
	# --replay-gain Calculate ReplayGain values and store them as FLAC tags, similar to vorbisgain.  Title gains/peaks will be computed for each input file, and an album gain/peak will be computed for all files. 
	# --best    Highest compression.
	
	# Ideas behind parameter decisions:
	# --silent Without silent, it will print each percent-value from 0 to 100 which would bloat logfiles.
	# --warnings-as-errors	This is clear - we want perfect output.
	# --output-prefix	We use it to put files into a subdirectory. We put them into a subdirectory so we can just use "*.flac" in further processing wtihout the risk of colliding with an eventually generated FLAC image or other files.
	# --verify	It is always a good idea to validate the output to make sure that it is good.
	# --replay-gain	Replaygain is generally something you should want. Go read up on it. TODO: We should use EBU-R128 instead, but as of Kubuntu12.04 there seems to be no package which can do it.
	# --best	Because we do PERFECT rips, we only need to do them once in our life and can just invest the time of maximal compression.
	# TODO: proof-read option list again
	
	set_working_directory_or_die "$inputdir"	# We need input filenames to be relative for --output-prefix to work
	if ! flac --silent --warnings-as-errors --output-prefix="$outputdir/" --verify --replay-gain --best *.wav ; then
		die "Encoding WAV to FLAC singletracks failed!"
	fi
	set_working_directory_or_die
	
	if [ ${UNIT_TESTS["TEST_DAMAGE_TO_FLAC_SINGLETRACKS"]} -eq 1 ]; then 
		log_and_stderr "Deliberately damaging a FLAC singletrack to test flac --test verification..."
		local flac_files=( "$outputdir/"*.flac )
		truncate --size=-1 "${flac_files[0]}" # We truncate the file instead of appending garbage because FLAC won't detect trailing garbage. TODO: File a bug report
	fi
}

# Because cuetools is bugged and won't print the catalog number we read it on our own
cue_get_catalog() {
	local regexp="^(CATALOG )(.+)\$"
	# The tr will convert CRLF to LF and prevend trainling CR on the output catalog value
	cat "$INPUT_CUE_ABSOLUTE" | tr -d '\r' | grep -E "$regexp" | sed -r s/"$regexp"/\\2/
}

get_version_string() {
	# defining & assigning them at once would overwrite $?
	local accurateripchecksum_version
	local cuetools_installation_state
	local cuetools_version
	local eaccrc_version
	local flac_version
	local shntool_version
	
	if ! accurateripchecksum_version="$(accuraterip-checksum --version)" ; then
		die "Obtaining accuraterip-checksum version failed! Please check whether it is installed."
	fi
	
	# As of 2012-12-23, cueprint does not support printing its version number. So we instead add the package version of cuetools
	# TODO: Add cueprint version once cueprint supports printing it.
	
	# The behavior of dpkg-query version number printing seems to be the following as of 2012-12-19:
	# 1. If the package is NOT installed, the highest available version number in the repository is printed.
	# 2. If the package is installed, the installed version is printed.
	# 3. If there is an update to the package available and even downloaded, it still prints the installed version.
	# This is not documented, I have found it out by testing.
	# As you can see, this contains the glitch of being ambious between the version number of not installed packages and installed ones.
	#
	# So we first have to check whether cuetools is installed and only use the version number if it actually is installed.
	# (Of course the script would fail anyway if cuetools was not installed but in case someone recycles this function then it will at least not have bugs)
	if ! cuetools_installation_state="$(dpkg-query --show --showformat='${Status}' cuetools)" ; then
		die "Checking cuetools installation state failed!"
	fi
	
	if [ "$cuetools_installation_state" != "install ok installed" ] ; then 
		die "cuetools is not installed! cuetools_installation_state=$cuetools_installation_state"
	fi
	
	if ! cuetools_version="$(dpkg-query --show --showformat='cuetools version ${Version}' cuetools)" ; then
		die "Obtaining cuetools version failed!"
	fi

	
	if ! eaccrc_version="$(eac-crc --version)" ; then
		die "Obtaining eac-crc version failed! Please check whether it is installed."
	fi
	
	if ! flac_version="$(flac --version)" ; then
		die "Obtaining flac version failed! Please check whether it is installed."
	fi
	
	if ! shntool_version="$(shntool -v 2>&1 | head -1)" ; then
		die "Obtaining shntool version failed! Please check whether it is installed."
	fi
	
	echo "perfect-flac-encode $VERSION with $accurateripchecksum_version, $cuetools_version, $eaccrc_version, $flac_version, $shntool_version" 
}
# This function was inspired by the cuetag script of cuetools, taken from https://github.com/svend/cuetools
# It's license is GPL so this function is GPL as well. 
#
# parameters:
# $1 = full path of FLAC file
# $2 = track number of FLAC file
pretag_singletrack_flac_from_cue_or_die()
{
	local flac_file="$1"
	local trackno="$2"

	# REASONS OF THE DECISIONS OF MAPPING CUE TAGS TO FLAC TAGS:
	#
	# Mapping CUE tag names to FLAC tag names is diffcult:
	# - CUE is not standardized. The tags it provides are insufficient to represent all tags of common types of music.Their meaning is not well-defined due to lag of standardization. Therefore, we only use the CUE fields which are physically stored on the CD.
	# - FLAC does provide a standard list of tags but it is as well insufficient. (http://www.xiph.org/vorbis/doc/v-comment.html) Therefore, we needed a different one
	#
	# Because we recommend MusicBrainz for tagging AND they are so kind to provide a complex list of standard tag names for each common audio file format including FLAC, we decided to use the MusicBrainz FLAC tag names. 
	# The "pre" means that tagging from a CUE is NEVER sufficient. CUE does not provide enough tags!
	#
	# Conclusion:
	# - The semantics of the CUE fields which EAC uses is taken from <TODO>
	# - The mapping between CUE tag names and cueprint fields is taken from the manpage of cueprint and by checking with an EAC CUE which uses ALL tags EAC will ever use (TODO: find one and actually do this)
	# - The target FLAC tag names are taken from http://musicbrainz.org/doc/MusicBrainz_Picard/Tags/Mapping
	#
	
	## From cueprint manpage:
	##   Character   Conversion         Character   Conversion
	##   ────────────────────────────────────────────────────────────────
	##   A           album arranger     a           track arranger
	##   C           album composer     c           track composer
	##   G           album genre        g           track genre
	##                                  i           track ISRC
	##   M           album message      m           track message
	##   N           number of tracks   n           track number
	##   P           album performer    p           track performer
	##   S           album songwriter
	##   T           album title        t           track title
	##   U           album UPC/EAN      u           track ISRC (CD-TEXT)

	# The following are the mappings from CUEPRINT to FLAC tags. The list was created by reading each entry of the above cueprint manpage and trying to find a tag which fits it in the musicbrainz tag mapping table http://musicbrainz.org/doc/MusicBrainz_Picard/Tags/Mapping
	# bash variable name == FLAC tag names
	# sorting of the variables is equal to cueprint manpage
	# TODO: find out the exact list of CUE-tags which cueprint CANNOT read and decide what to do about them
	# TODO: do a reverse check of the mapping list: read the musicbrainz tag mapping table and try to find a proper CUE-tag for each musicbrainz tag. ideally, as the CUE-tag-table, do not use the cueprint manpage but a list of all CUE tags which EAC will ever generate

	# We only use the fields which are actually stored on the disc.
	# TODO: find out whether this is actually everything which is stored on a CD
	
	local -A fields	# Attention: We have to explicitely declare the associative array or iteration over the keys will not work!
	
	# disc tags
	
	# album UPC/EAN. Debbuging showed that cueprint's %U is broken so we use our function.	
	if ! fields["CATALOGNUMBER"]="$(cue_get_catalog)" ; then
		die "cue_get_catalog failed!"
	fi

	# We use our own homebrew regexp for obtaining the CATALOG from the CUE so we should be careful
	if [ "${fields['CATALOGNUMBER']}" = "" ]; then
		die "Obtaining CATALOG failed!"
	fi

	fields["ENCODEDBY"]="$FULL_VERSION"							# own version :)
	fields["TRACKTOTAL"]='%N'													# number of tracks
	fields["TOTALTRACKS"]="${fields['TRACKTOTAL']}"								# musicbrainz lists both TRACKTOAL and TOTALTRACKS and for track count.

	# track tags
	fields["ISRC"]='%i'			# track ISRC
	fields["COMMENT"]='%m'		# track message. TODO: is this stored on the CD?
	fields["TRACKNUMBER"]='%n'	# %n = track number
		
	for field in "${!fields[@]}"; do
		# remove pre-existing tags. we do not use --remove-all-tags because it would remove the replaygain info. and besides it is also cleaner to only remove stuff we know about
		if ! metaflac --remove-tag="$field" "$flac_file" ; then
			die "Removing existing tag $field failed!"
		fi
		
		local conversion="${fields[$field]}"
		local value
		
		if ! value="$(cueprint -n $trackno -t "$conversion\n" "$INPUT_CUE_ABSOLUTE")" ; then
			die "cueprint failed!"
		fi
		
		if [ -z "$value" ] ; then
			continue	# Skip empty field
		fi
		
		local tag="$field=$value"
		
		if ! metaflac --set-tag="$tag" "$flac_file" ; then
			die "Setting tag $tag failed!"
		fi
	done
}

# This function was inspired by the cuetag script of cuetools, taken from https://github.com/svend/cuetools
# It's license is GPL so this function is GPL as well. 
pretag_singletrack_flacs_from_cue_or_die()
{
	log "Pre-tagging the singletrack FLACs with information from the CUE which is physically stored on the CD. Please use MusicBrainz Picard for the rest of the tags..."
	
	local flac_files=( "${TEMP_DIRS_ABSOLUTE[FLAC_SINGLETRACK_SUBDIR]}/"*.flac )
	
	for file in "${flac_files[@]}"; do
		local filename_without_path

		if ! filename_without_path="$(basename "$file")" ; then
			die "basename failed!"
		fi

		local tracknumber

		if ! tracknumber="$(get_tracknumber_of_singletrack "$filename_without_path")" ; then
			die "get_tracknumber_of_singletrack failed!"
		fi

		if ! pretag_singletrack_flac_from_cue_or_die "$file" "$tracknumber" ; then
			die "Tagging $file failed!"
		fi
	done
}

test_flac_singletracks_or_die() {
	log "Running flac --test on singletrack FLACs..."
	
	local flac_files=( "${TEMP_DIRS_ABSOLUTE[FLAC_SINGLETRACK_SUBDIR]}"/*.flac )
	
	if ! flac --test --silent --warnings-as-errors "${flac_files[@]}"; then
		die "Testing FLAC singletracks failed!"
	fi
}

test_checksums_of_decoded_flac_singletracks_or_die() {
	log "Decoding singletrack FLACs to WAVs to validate checksums ..."
	
	local inputdir_wav="${TEMP_DIRS_ABSOLUTE[WAV_SINGLETRACK_SUBDIR]}"
	local inputdir_flac="${TEMP_DIRS_ABSOLUTE[FLAC_SINGLETRACK_SUBDIR]}"
	local outputdir="${TEMP_DIRS_ABSOLUTE[DECODED_WAV_SINGLETRACK_SUBDIR]}"
	
	set_working_directory_or_die "$inputdir_flac"	# We need input filenames to be relative for --output-prefix to work
	if ! flac --decode --silent --warnings-as-errors --output-prefix="$outputdir/" *.flac ; then
		die "Decoding FLAC singletracks failed!"
	fi
	set_working_directory_or_die
	
	if [ ${UNIT_TESTS["TEST_DAMAGE_TO_DECODED_FLAC_SINGLETRACKS"]} -eq 1 ]; then 
		local wav_files=( "$outputdir/"*.wav )
		log_and_stderr "Deliberately damaging a decoded WAV singletrack to test checksum verification..."
		echo "FAIL" >> "${wav_files[0]}"
	fi

	log "Generating checksums of original WAV files..."
	# We do NOT use absolute paths when calling sha256sum to make sure that the checksum file contains relative paths.
	# This is absolutely crucical because when validating the checksums we don't want to accidentiall check the sums of the input files instead of the output files.
	set_working_directory_or_die "$inputdir_wav"
	if ! sha256sum --binary *.wav > "checksums.sha256" ; then
		die "Generating input checksums failed!"
	fi
	set_working_directory_or_die
	
	log "Validating checksums of decoded WAV singletracks ..."
	set_working_directory_or_die "$outputdir"
	local sha_output
	if ! sha_output="$(sha256sum --check --strict "$inputdir_wav/checksums.sha256")" ; then
		log_and_stderr "$sha_output"
		die "Validating checksums of decoded WAV singletracks failed!"
	else
		log "$sha_output"
		log "All checksums OK."
	fi
	set_working_directory_or_die
}

move_output_to_target_dir_or_die() {
	log "Moving FLACs to output directory..."
	
	if ! mv --no-clobber "${TEMP_DIRS_ABSOLUTE[FLAC_SINGLETRACK_SUBDIR]}"/*.flac "$OUTPUT_DIR_ABSOLUTE" ; then
		die "Moving FLAC files to output dir failed!"
	fi
}

copy_cue_and_log_to_target_dir_or_die() {
	log "Copying CUE and LOG to output directory..."
	
	if ! cp --archive --no-clobber "$INPUT_CUE_ABSOLUTE" "$OUTPUT_DIR_ABSOLUTE" ; then
		die "Copying CUE to output directory failed!"
	fi
	
	if ! cp --archive --no-clobber "$INPUT_LOG_ABSOLUTE" "$OUTPUT_DIR_ABSOLUTE/Exact Audio Copy.log" ; then
		die "Copying LOG to output directory failed!"
	fi
}

# Prints the README to stdout.
print_readme_or_die() {
	local e="echo"
	
	$e "About the quality of this CD copy:" &&
	$e "----------------------------------" &&
	$e "These audio files were produced with perfect-flac-encode."  &&
	$e "They are stored in \"FLAC\" format, which is lossless. This means that they can have the same quality as an audio CD." &&
	$e "This is much better than MP3 for example: MP3 leaves out some tones because some people cannot hear them." &&
	$e "" &&
	$e "The used prefect-flac-encode is a program which converts good Exact Audio Copy CD copies to FLAC audio files." &&
	$e "The goal of perfect-flac-encode is to produce CD copies with the best quality possible." &&
	$e "This is NOT only about the quality of the audio: It also means that the files can be used as a perfect backup of your CDs. The author of the software even trusts them for digital preservation for ever." &&
	$e "For allowing this, the set of files which you received were designed to make it possible to burn a disc which is absolutely identical to the original one in case your original disc is destroyed." &&
	$e "Therefore, please do not delete any of the contained files!" &&
	$e "For instructions on how to restore the original disc, please visit the website of perfect-flac-decode. You can find the address below." &&
	$e "" &&
	$e "" &&
	$e "Explanation of the purpose of the files you got:" &&
	$e "------------------------------------------------" &&
	$e "\"$INPUT_CUE_LOG_WAV_BASENAME.cue\"" &&
	$e "This file contains the layout of the original disc. It will be the file which you load with your CD burning software if you want to burn a backup of the disc. Please remember: Before burning it you have to decompress the audio with perfect-flac-decode. If you don't do this, burning the 'cue' will not work." &&
	$e "" &&
	$e "\"$INPUT_CUE_LOG_WAV_BASENAME.sha256\"" &&
	$e "This contains a so-called checksum of the original, uncompressed disc image. If you want to burn the disc to a CD, you will have to decompress the FLAC files to a WAV image with perfect-flac-decode. The checksum file allows perfect-flac-decode to validate that the decompression did not produce any errors." &&
	$e "" &&
	$e "\"Exact Audio Copy.log\"" &&
	$e "This file is a 'proof of quality'. It contains the output of Exact Audio Copy - the software which was used to extract the physical CD to a computer. It allows you to see the conditions of the copying and the version of Exact Audio Copy. You can check it to see that there were no errors. Further, if someone finds bugs in certain versions of Exact Audio Copy you will be able to check whether your audio files are affected by examining the version number." &&
	$e "" &&
	$e "\"Perfect-FLAC-Encode.log\"" &&
	$e "This file is a 'proof of quality'. It contains the output of perfect-flac-encode and the version of it and the versions of all used helper programs. It allows you to see the conditions of the encoding process. You can check it to see that there were no errors. Further, if someone finds bugs in certain versions of perfect-flac-encode or the helper programs you will be able to check whether your audio files are affected by examining the version numbers." &&
	$e "" &&
	$e "" &&
	$e "Websites:" &&
	$e "---------" &&
	$e "perfect-flac-encode: http://leo.bogert.de/perfect-flac-encode" &&
	$e "perfect-flac-decode: http://leo.bogert.de/perfect-flac-decode" &&
	$e "FLAC: http://flac.sourceforge.net/" &&
	$e "Exact Audio Copy: http://www.exactaudiocopy.de/"
}

write_readme_txt_to_target_dir_or_die() {
	log "Generating README.txt ..."

	# We wrap at standard 80 chars terminal-style width so we have a better chance of fititng into a standard Notepad window.
	# Notice that the width of Notepad seems to be configured from the screen resolution at first startup so we ought to be conservative.
	# We use Windows linebreaks since they will work on any plattform. Unix linebreaks would not wrap the line with many Windows editors.
	if ! print_readme_or_die |
		fold --spaces --width=80 | 	
		( while read line; do echo -n -e "$line\r\n"; done ) \
		> "$OUTPUT_DIR_ABSOLUTE/README.txt"	
	then
		die "Generating README.txt failed!"
	fi
}

die_if_unit_tests_failed() {
	for test in "${!UNIT_TESTS[@]}"; do
		if [ "${UNIT_TESTS[$test]}" != "0" ] ; then
			die "Unit test $test failed: perfect-flac-encode should have indicated checksum failure due to the deliberate damage of the unit test but did not do so!"
		fi
	done
}

err_handler() {
	die "error at line $1" "last exit code is $2" 
}

enable_errexit_and_errtrace() {
	set -o errexit
	set -o errtrace
	trap 'err_handler "$LINENO" "$?"' ERR
}

main() {
# TODO FIXME XXX: Enable the following. This is a TODO because the script will need some modifications to not execute any commands which trigger errexit unnecessarily
#	enable_errexit_and_errtrace

	if ! FULL_VERSION="$(get_version_string)" ; then
		die "Obtaining version identificator failed. Check whether all required tools are installed!"
	fi
	
	# obtain parameters

	local original_working_dir # store the working directory in case the parameters are relative paths

	if ! original_working_dir="$(pwd)" ; then
		die "pwd failed!"
	fi

	local original_cue_log_wav_basename="$1"
	local input_dir="$2"
	local output_dir="$3"
	
	# initialize globals
	INPUT_CUE_LOG_WAV_BASENAME="$original_cue_log_wav_basename"
	
	# strip trailing slash as long as the dir is not "/"
	[[ "$input_dir" != "/" ]] && input_dir="${input_dir%/}"
	[[ "$output_dir" != "/" ]] && output_dir="${output_dir%/}"
	# make the directories absolute if they are not
	[[ "$input_dir" = /* ]] && INPUT_DIR_ABSOLUTE="$input_dir" || INPUT_DIR_ABSOLUTE="$original_working_dir/$input_dir"
	[[ "$output_dir" = /* ]] && OUTPUT_DIR_ABSOLUTE="$output_dir/$INPUT_CUE_LOG_WAV_BASENAME" || OUTPUT_DIR_ABSOLUTE="$original_working_dir/$output_dir/$INPUT_CUE_LOG_WAV_BASENAME"
	
	OUTPUT_OWN_LOG_ABSOLUTE="$OUTPUT_DIR_ABSOLUTE/Perfect-FLAC-Encode.log"

	OUTPUT_SHA256_ABSOLUTE="$OUTPUT_DIR_ABSOLUTE/$INPUT_CUE_LOG_WAV_BASENAME.sha256"
	
	INPUT_CUE_ABSOLUTE="$INPUT_DIR_ABSOLUTE/$INPUT_CUE_LOG_WAV_BASENAME.cue"
	INPUT_LOG_ABSOLUTE="$INPUT_DIR_ABSOLUTE/$INPUT_CUE_LOG_WAV_BASENAME.log"
	INPUT_WAV_ABSOLUTE="$INPUT_DIR_ABSOLUTE/$INPUT_CUE_LOG_WAV_BASENAME.wav"
	
	for tempdir in "${!TEMP_DIRS[@]}" ; do
		TEMP_DIRS_ABSOLUTE[$tempdir]="$OUTPUT_DIR_ABSOLUTE/${TEMP_DIRS[$tempdir]}"
	done
	
	# All variables are set up now
	# We need to make the output directory available now so log() works

	stdout "Input directory: $INPUT_DIR_ABSOLUTE"
	stdout "Output directory: $OUTPUT_DIR_ABSOLUTE"
	
	ask_to_delete_existing_output_and_temp_dirs_or_die
	create_directories_or_die
	set_working_directory_or_die
	create_log_file_or_die

	# The output directory exists, we are inside of it, logging works. Now we can actually deal with the audio part.
	
	log_and_stdout "$FULL_VERSION running ... "
	log_and_stderr "BETA VERSION - NOT for productive use!"
	log_and_stdout "Album: $original_cue_log_wav_basename"
	
	check_whether_input_is_accurately_ripped_or_die
	check_shntool_wav_problem_diagnosis_or_die
	test_whether_the_two_eac_crcs_match_or_die
	test_eac_crc_or_die
	split_wav_image_to_singletracks_or_die
	test_accuraterip_checksums_of_split_wav_singletracks_or_die
	generate_checksum_of_original_wav_image_or_die
	test_checksum_of_rejoined_wav_image_or_die
	encode_wav_singletracks_to_flac_or_die
	pretag_singletrack_flacs_from_cue_or_die
	test_flac_singletracks_or_die
	test_checksums_of_decoded_flac_singletracks_or_die
	move_output_to_target_dir_or_die
	copy_cue_and_log_to_target_dir_or_die
	write_readme_txt_to_target_dir_or_die
	delete_temp_dirs
	die_if_unit_tests_failed
	
	log_and_stdout "SUCCESS."
	exit 0 # SUCCESS
}

main "$@"
