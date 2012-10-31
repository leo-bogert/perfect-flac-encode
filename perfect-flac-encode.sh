#!/bin/bash

# See https://github.com/leo-bogert/perfect-flac-encode/blob/master/README.md for Syntax etc.

#################################################################
# Configuration:
#################################################################
wav_singletrack_subdir="Stage1_WAV_Singletracks_From_WAV_Image"
wav_jointest_subdir="Stage2_WAV_Image_Joined_From_WAV_Singletracks"
flac_singletrack_subdir="Stage3_FLAC_Singletracks_Encoded_From_WAV_Singletracks"
decoded_wav_singletrack_subdir="Stage4_WAV_Singletracks_Decoded_From_FLAC_Singletracks"

temp_dirs_to_delete=( "$wav_singletrack_subdir" "$wav_jointest_subdir" "$flac_singletrack_subdir" "$decoded_wav_singletrack_subdir" )

# "Unit tests": Enabling these will damage the produced output files to test the checksum verification
# Notice that only enabling one at once makes sense because the script will terminate if ANY checksum verification fails :)
# Set to 1 to enable
test_damage_to_split_wav_singletracks=0
test_damage_to_rejoined_wav_image=0
test_damage_to_flac_singletracks=0
test_damage_to_decoded_flac_singletracks=0
#################################################################
# End of configuration
#################################################################



#################################################################
# Global variables
#################################################################
VERSION=BETA3
#################################################################
# End of global variables
#################################################################


# parameters: $1 = target working directory
set_working_directory_or_die() {
	#echo "Changing working directory to $1..."
	if ! cd "$1" ; then
		echo "Setting working directory failed!" >&2
		exit 1
	fi
}

# parameters:
# $1 = output dir 
ask_to_delete_existing_output_and_temp_dirs_or_die() {
	local output_dir_and_temp_dirs=( "${temp_dirs_to_delete[@]}" "$1" )
	local confirmed=n
	
	for existingdir in "${output_dir_and_temp_dirs[@]}" ; do
		if [ -d "$working_dir_absolute/$existingdir" ]; then
			[ "$confirmed" == "y" ] || read -p "The output and/or temp directories exist already. Delete them and ALL contained files? (y/n)" confirmed
		
			if [ "$confirmed" == "y" ]; then
				rm --preserve-root -rf "$working_dir_absolute/$existingdir"
			else
				echo "Quitting because you want to keep the existing output."
				exit 1
			fi
		fi
	done
}

delete_temp_dirs() {
	echo "Deleting temp directories..."
	for existingdir in "${temp_dirs_to_delete[@]}" ; do
		if [ -d "$working_dir_absolute/$existingdir" ]; then
			if ! rm --preserve-root -rf "$working_dir_absolute/$existingdir" ; then
				echo "Deleting the temp files failed!"
				exit 1
			fi
		fi
	done
}

# parameters:
# $1 = filename of cue/wav/log
check_whether_input_is_accurately_ripped_or_die() {
	echo "Checking EAC LOG for whether AccurateRip reports a perfect rip..."
	
	if ! iconv --from-code utf-16 --to-code utf-8 "$1.log" | grep --quiet "All tracks accurately ripped" ; then
		echo "AccurateRip reported that the disk was not ripped properly - aborting!"
		exit 1
	else
		echo "AccurateRip reports a perfect rip."
	fi
}

# parameters:
# $1 = filename of cue/wav/log
split_wav_image_to_singletracks_or_die() {
	echo "Splitting WAV image to singletrack WAVs..."
	
	local outputdir_relative="$wav_singletrack_subdir"
	
	set_working_directory_or_die "$working_dir_absolute"
	
	if ! mkdir -p "$outputdir_relative" ; then
		echo "Making $outputdir_relative subdirectory failed!" >&2
		exit 1
	fi
	
	# shntool syntax:
	# -D = print debugging information
	# -P type Specify progress indicator type. dot shows the progress of each operation by displaying a '.' after each 10% step toward completion.
	# -d dir Specify output directory 
	# -o str Specify output file format extension, encoder and/or arguments.  Format is:  "fmt [ext=abc] [encoder [arg1 ... argN (%f = filename)]]"
	# -f file Specifies a file from which to read split point data.  If not given, then split points are read from the terminal.
    # TODO: we can replace special characters in filenames generated from cuesheets with "-m". is this needed or does EAC already do it properly?
	# -n fmt Specifies the file count output format.  The default is %02d, which gives two‐digit zero‐padded numbers (01, 02, 03, ...).
	# -t fmt Name output files in user‐specified format based on CUE sheet fields. %t Track title, %n Track number
	# -- = indicates that everything following it is a filename
	
	# Ideas behind parameter decisions:
	# - We specify a different progress indicator so redirecting the script output to a log file will not result in a bloated file"
	# - We do NOT let shntool encode the FLAC files on its own. While testing it has shown that the error messages of FLAC are not printed. Further, because we want this script to be robust, we only use the core features of each tool and not use fancy stuff which they were not primarily designed for.
	# - We split the tracks into a subdirectory so when encoding the files we can just encode "*.wav", we don't need any mechanism for excluding the image WAV
	# - We prefix the filename with the maximal amount of zeroes required to get proper sorting for the maximal possible trackcount on a CD which is 99. We do this because cuetag requires proper sort order of the input files and we just use "*.flac" for finding the input files

	# For making the shntool output more readable we don't use absolute paths but changed the working directory above.
	if ! shntool split -P dot -d "$outputdir_relative" -f "$1.cue" -n %02d -t "%n - %t" -- "$1.wav" ; then
		echo "Splitting WAV image to singletracks failed!" >&2
		exit 1
	fi
	
	local outputdir_absolute="$working_dir_absolute/$outputdir_relative"
	local wav_singletracks=( "$outputdir_absolute"/*.wav )
	set_working_directory_or_die "$outputdir_absolute"
	if [ "$test_damage_to_split_wav_singletracks" -eq 1 ]; then 
		echo "Deliberately damaging a singletrack to test the AccurateRip checksum verification ..."
		if ! shntool gen -l 1:23 ; then 
			echo "Generating silent WAV file failed!"
			exit 1
		fi
		if ! mv "silence.wav" "${wav_singletracks[0]}" ; then
			echo "Overwriting track 0 with silence failed!"
			exit 1
		fi
	fi
	set_working_directory_or_die "$working_dir_absolute"
}

# parameters:
# $1 = filename of cue/wav/logs
# $2 = tracknumber
get_accuraterip_checksum_of_singletrack_or_die() {
	local filename="$working_dir_absolute/$1.log"
	local tracknumber="$2"
	tracknumber=`echo "$tracknumber" | sed 's/0*//'`	# remove leading zeros, the EAC LOG does not contain them

	# Difficult solution using grep:
	#iconv --from-code utf-16 --to-code utf-8 "$filename" | grep -E "Track( {1,2})([[:digit:]]{1,2})( {2})accurately ripped \\(confidence ([[:digit:]]*)\\)  \\[([0-9A-Fa-f]*)\\]" | grep -E "Track( {1,2})$tracknumber( {2})" | grep -E -o "\\[([0-9A-Fa-f]*)\\]" | grep -E -o "([0-9A-Fa-f]*)"
	
	# Easy solution using bash:
	log=`cat "$filename"`
	regex="Track( {1,2})($tracknumber)( {2})accurately ripped \\(confidence ([[:digit:]]*)\\)  \\[([0-9A-Fa-f]*)\\]"
	if [[ $log =~ $regex  ]] ; then
		i=0
		
		# TODO: why doesn't this work?
		# echo "${BASH_REMATCH[9]}"
		
		# because the above doesn't work we have to loop over the array:
		for group in ${BASH_REMATCH[@]} ; do
			if [[ i -eq 9 ]]; then
				echo "$group"
				return 0
			fi
			let i++
		done
	else
		echo "Regexp for getting the AccurateRip checksum failed!" >&2
		exit 1
	fi
}

# parameters:
# $1 = full filename
get_tracknumber_of_wav_singletrack() {
	filename="$1"
	echo "$filename" | grep -E -o "^([[:digit:]]{2}) -" | grep -E -o "([[:digit:]]{2})"
	# TODO: Use bash regexp as soon as the bug in get_accuraterip_checksum_of_singletrack_or_die which prevents direct access on BASH_REMATCH is fixed
}

# parameters:
# $1 = directory which contains the wav singletracks only
get_total_wav_tracks() {
	local inputdir_wav="$1"
	local tracks=( "$inputdir_wav"/*.wav )
	echo "${#tracks[@]}"
}

# parameters:
# $1 = filename of cue/wav/log
test_accuraterip_checksums_of_split_wav_singletracks_or_die() {
	echo "Comparing AccurateRip checksums of split WAV singletracks to AccurateRip checksums from EAC LOG..."
	
	local inputdir_wav="$working_dir_absolute/$wav_singletrack_subdir"
	local wav_singletracks=( "$inputdir_wav"/*.wav )
	local totaltracks=`get_total_wav_tracks "$inputdir_wav"`
	
	for filename in "${wav_singletracks[@]}"; do
		filename_without_path=`basename "$filename"`
		tracknumber=`get_tracknumber_of_wav_singletrack "$filename_without_path"`
		expected_checksum=`get_accuraterip_checksum_of_singletrack_or_die "$1" "$tracknumber"`
		expected_checksum=${expected_checksum^^} # convert to uppercase
		actual_checksum=`~/accuraterip-checksum "$filename" "$tracknumber" "$totaltracks"`	#TODO: obtain an ubuntu package for this and use the binary from PATH, not ~
	
		if [ "$actual_checksum" != "$expected_checksum" ]; then
			echo "AccurateRip shecksum mismatch for track $tracknumber: expected=$expected_checksum; actual=$actual_checksum" >&2
			exit 1
		else
			echo "AccurateRip checksum of track $tracknumber: $actual_checksum, expected $expected_checksum. OK."
		fi
	done
}

# parameters:
# $1 = filename of cue/wav/log
test_checksum_of_rejoined_wav_image_or_die() {
	echo "Joining singletrack WAV temporarily for comparing their checksum with the original image's checksum..."	
	
	local inputdir_relative="$wav_singletrack_subdir"
	local outputdir_relative="$wav_jointest_subdir"
	local original_image="$working_dir_absolute/$1.wav"
	local joined_image="$working_dir_absolute/$outputdir_relative/joined.wav"
	
	set_working_directory_or_die "$working_dir_absolute"
	
	if ! mkdir -p "$outputdir_relative" ; then
		echo "Making $outputdir_relative subdirectory failed!" >&2
		exit 1
	fi
	
	# shntool syntax:
	# -D = print debugging information
	# -P type Specify progress indicator type. dot shows the progress of each operation by displaying a '.' after each 10% step toward completion.
	# -d dir Specify output directory 
	# -- = indicates that everything following it is a filename
	
	# Ideas behind parameter decisions:
	# - We specify a different progress indicator so redirecting the script output to a log file will not result in a bloated file"
	# - We join into a subdirectory because we don't need the joined file afterwards and we can just delete the subdir to get rid of it
	if ! shntool join -P dot -d "$outputdir_relative" -- "$inputdir_relative"/*.wav ; then
		echo "Joining WAV failed!" >&2
		exit 1
	fi
	
	if [ "$test_damage_to_rejoined_wav_image" -eq 1 ]; then 
		echo "Deliberately damaging the joined image to test the checksum verification ..."
		echo "FAIL" >> "$joined_image"
	fi
	
	original_sum=( `sha256sum --binary "$original_image"` )	# it will also print the filename so we split the output by spaces to an array and the first slot will be the actual checksum
	joined_sum=( `sha256sum --binary "$joined_image"` )
	
	# TODO: What about the checksum in the EAC-LOG? Is it a plain CRC32 or a magic checksum with some samples excluded?
	# If it is no plain checksum then we should keep the sha256sum for the user so he can check his restored image
	
	echo "Computing checksums..."
	
	echo -e "Original checksum: \t\t${original_sum[0]}"
	echo -e "Checksum of joined image:\t${joined_sum[0]}"
	
	if [ "${original_sum[0]}" != "${joined_sum[0]}" ]; then
		echo "Checksum of joined image does not match original checksum!"
		exit 1
	fi
	
	echo "Checksum of joined image OK."
}

encode_wav_singletracks_to_flac_or_die() {
	echo "Encoding singletrack WAVs to FLAC ..."
	
	local inputdir="$working_dir_absolute/$wav_singletrack_subdir"
	local outputdir="$working_dir_absolute/$flac_singletrack_subdir"
	
	if ! mkdir -p "$outputdir" ; then
		echo "Making $outputdir subdirectory failed!" >&2
		exit 1
	fi
	
	# used flac parameters:
	# --silent	Silent mode (do not write runtime encode/decode statistics to stderr)
	# --warnings-as-errors	Treat all warnings as errors (which cause flac to terminate with a non-zero exit code).
	# --output-prefix=string	Prefix  each output file name with the given string.  This can be useful for encoding or decoding files to a different directory. 
	# --keep-foreign-metadata	If  encoding,  save  WAVE  or  AIFF non-audio chunks in FLAC metadata. If decoding, restore any saved non-audio chunks from FLAC metadata when writing the decoded file. 
	# --verify	Verify a correct encoding by decoding the output in parallel and comparing to the original
	# --replay-gain Calculate ReplayGain values and store them as FLAC tags, similar to vorbisgain.  Title gains/peaks will be computed for each input file, and an album gain/peak will be computed for all files. 
	# --best    Highest compression.
	
	# Ideas behind parameter decisions:
	# --silent Without silent, it will print each percent-value from 0 to 100 which would bloat logfiles.
	# --warnings-as-errors	This is clear - we want perfect output.
	# --output-prefix	We use it to put files into a subdirectory. We put them into a subdirectory so we can just use "*.flac" in further processing wtihout the risk of colliding with an eventually generated FLAC image or other files.
	# --keep-foreign-metadata	We assume that it is necessary for being able to decode to bitidentical WAV files. TODO: Validate this.
	# --verify	It is always a good idea to validate the output to make sure that it is good.
	# --replay-gain	Replaygain is generally something you should want. Go read up on it. TODO: We should use EBU-R128 instead, but as of Kubuntu12.04 there seems to be no package which can do it.
	# --best	Because we do PERFECT rips, we only need to do them once in our life and can just invest the time of maximal compression.
	# TODO: proof-read option list again
	
	set_working_directory_or_die "$inputdir"	# We need input filenames to be relative for --output-prefix to work
	if ! flac --silent --warnings-as-errors --output-prefix="$outputdir/" --keep-foreign-metadata --verify --replay-gain --best *.wav ; then
		echo "Encoding WAV to FLAC singletracks failed!" >&2
		exit 1
	fi
	set_working_directory_or_die "$working_dir_absolute"
	
	local flac_files=( "$outputdir/"*.flac )
	if [ "$test_damage_to_flac_singletracks" -eq 1 ]; then 
		echo "Deliberately damaging a FLAC singletrack to test flac --test verification..."
		echo "FAIL" > "${flac_files[0]}" # TODO: We overwrite the whole file because FLAC won't detect trailing garbage. File a bug report
	fi
}

test_flac_singletracks_or_die() {
	echo "Running flac --test on singletrack FLACs..."
	local inputdir_flac="$working_dir_absolute/$flac_singletrack_subdir"
	
	set_working_directory_or_die "$inputdir_flac"	# We need input filenames to be relative for --output-prefix to work
	local flac_files=( *.flac )
	
	if ! flac --test --silent --warnings-as-errors "${flac_files[@]}"; then
		echo "Testing FLAC singletracks failed!" >&2
		exit 1
	fi
}

test_checksums_of_decoded_flac_singletracks_or_die() {
	echo "Decoding singletrack FLACs to WAVs to validate checksums ..."
	
	local inputdir_wav="$working_dir_absolute/$wav_singletrack_subdir"
	local inputdir_flac="$working_dir_absolute/$flac_singletrack_subdir"
	local outputdir="$working_dir_absolute/$decoded_wav_singletrack_subdir"
	
	if ! mkdir -p "$outputdir" ; then
		echo "Making $outputdir subdirectory failed!" >&2
		exit 1
	fi
	
	set_working_directory_or_die "$inputdir_flac"	# We need input filenames to be relative for --output-prefix to work
	if ! flac --decode --silent --warnings-as-errors --output-prefix="$outputdir/" --keep-foreign-metadata *.flac ; then
		echo "Decoding FLAC singletracks failed!" >&2
		exit 1
	fi
	set_working_directory_or_die "$working_dir_absolute"
	
	local wav_files=( "$outputdir/"*.wav )
	if [ "$test_damage_to_decoded_flac_singletracks" -eq 1 ]; then 
		echo "Deliberately damaging a decoded WAV singletrack to test checksum verification..."
		echo "FAIL" >> "${wav_files[0]}"
	fi

	echo "Generating checksums of original WAV files..."
	# We do NOT use absolute paths when calling sha256sum to make sure that the checksum file contains relative paths.
	# This is absolutely crucical because when validating the checksums we don't want to accidentiall check the sums of the input files instead of the output files.
	set_working_directory_or_die "$inputdir_wav"
	if ! sha256sum --binary *.wav > "checksums.sha256" ; then
		echo "Generating input checksums failed!" &> 2
		exit 1
	fi
	
	echo "Validating checksums of decoded WAV singletracks ..."
	set_working_directory_or_die "$outputdir"
	if ! sha256sum --check --strict "$inputdir_wav/checksums.sha256" ; then
		echo "Validating checksums of decoded WAV singletracks failed!" >&2
		exit 1
	else
		echo "All checksums OK."
	fi
	set_working_directory_or_die "$working_dir_absolute"
}

# parameters:
# $1 = target subdir
move_output_to_target_dir() {
	echo "Moving output to output directory..."
	
	local inputdir="$working_dir_absolute/$flac_singletrack_subdir"
	local outputdir="$working_dir_absolute/$1"
	
	if ! mkdir -p "$outputdir" ; then
		echo "Making $outputdir subdirectory failed!" >&2
		exit 1
	fi
	
	if ! mv --no-clobber "$inputdir"/*.flac "$outputdir" ; then
		echo "Moving FLAC files to output dir failed!" >&2
		exit 1
	fi
}

# parameters:
# $1 = filename of CUE/LOG
# $2 = target subdirectory
copy_cue_log_to_target_dir() {
	echo "Copying CUE and LOG to output directory..."
	
	local inputdir="$working_dir_absolute"
	local outputdir="$working_dir_absolute/$2"
	
	if ! cp --archive --no-clobber "$inputdir/$1.cue" "$inputdir/$1.log" "$outputdir" ; then
		"Copying CUE/LOG failed!" >&2
		exit 1;
	fi
}


main() {
	echo -e "\n\nperfect-flac-encode.sh Version $VERSION running ... "
	echo -e "BETA VERSION - NOT for productive use!\n\n"

	# parameters
	local rip_dir_absolute="$1"
	local input_wav_log_cue_filename="$2"
	local output_dir="$input_wav_log_cue_filename"
	
	echo "Album: $input_wav_log_cue_filename"
	
	# globals
	working_dir_absolute="$rip_dir_absolute"

	set_working_directory_or_die "$working_dir_absolute"
	
	ask_to_delete_existing_output_and_temp_dirs_or_die "$output_dir"
	check_whether_input_is_accurately_ripped_or_die "$input_wav_log_cue_filename"
	
	#compress_image_wav_to_image_flac_or_die "$@"	
	split_wav_image_to_singletracks_or_die "$input_wav_log_cue_filename"
	test_accuraterip_checksums_of_split_wav_singletracks_or_die "$input_wav_log_cue_filename"
	test_checksum_of_rejoined_wav_image_or_die "$input_wav_log_cue_filename"
	encode_wav_singletracks_to_flac_or_die
	test_flac_singletracks_or_die
	test_checksums_of_decoded_flac_singletracks_or_die
	move_output_to_target_dir "$output_dir"
	copy_cue_log_to_target_dir "$input_wav_log_cue_filename" "$output_dir"
	# TODO: Copy cue/log/(sha256 as soon as th TODO for generating it is resolved) to the output dir
	delete_temp_dirs
	
	echo "SUCCESS. Your FLACs are in directory \"$input_wav_log_cue_filename\""
	exit 0 # SUCCESS
}

main "$@"
