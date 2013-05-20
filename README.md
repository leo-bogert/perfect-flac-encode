perfect-flac-encode
===================

# Description:
This is an encoder script for EAC "Test & copy image" mode.
It splits the WAV image to WAV singletracks according to the EAC CUE and encodes them to FLACs.
Its primary goal is to produce perfect FLAC files by verifying checksums in all steps and being totally paranoid.
For guaranteeing this, it does the following checks and aborts if any of them fails:

1. It checks the EAC LOG to make sure that AccurateRip reported a flawless rip.
2. It uses shntool len to check for any of the following problems with the input WAV:
	* Data is not CD quality
	* Data is not cut on a sector boundary
	* Data is too short to be burned
	* Header is not canonical
	* Contains extra RIFF chunks
	* Contains an ID3v2 header
	* Audio data is not block‐aligned
	* Header is inconsistent about data size and/or file size
	* File is truncated
	* File has junk appended to it
3. It checks whether the Test and Copy CRC in the EAC LOG match.
4. It computes the EAC CRC of the input WAV image and checks whether it matches the Copy CRC in the EAC LOG.
5. It computes the AccurateRip checksums of the splitfiles which it has created and compares them with the ones from the EAC LOG.
6. It re-joins the singletrack files to an image and compares the checksum with the checksum of the original image from EAC to make sure that it would be possible to burn an identical CD again.
7. It encodes the singletracks to FLAC with very carefully chosen settings. The full manpage of FLAC was read by me when chosing the settings.
8. It runs flac --test on each singletrack which makes FLAC test the integrity of the file.
9. It decodes each singletrack to WAV again and compares the checksums with the checksums of the original WAV splitfiles.

The secondary goal is providing a perfect backup of the original disc. For serving this purpose, it is ensured that it is technically possible to burn a disc of which every bit is identical to the original one. This is guaranteed by:

* Copying a specification of the configuration of EAC to the output directory.
* Copying the original CUE/LOG to the output directory. The CUE is needed for burning the disc. The LOG serves as a proof of quality.
* Logging its own processing to a separate log file in the output. It will show proof that all the 9 steps mentioned above worked properly.
* A .sha256 file is generated which contains the SHA256-checksum of the original WAV image. For being able to burn a bit-identical CD, the user will have to decode the FLACs to WAVs and re-join the WAVs to an image. For making sure that this produced an image which is identical to the original one, the SHA256-checksum can be used. Notice that the CRC from the EAC LOG is not suitable for this because it is a "custom" CRC which is not computed upon the full WAV file. The EAC CRC does guarantee integrity of the audio data but is not easy to verify with standard tools.
* A README.txt is written to the output directory. It tries to explain in layman's terms how the rip was created, which software was used, that the rip should be high quality, which files are in the directory, and how to restore an identical CD.

Additional features are:

* The following tags are added to the FLACs: TRACKTOTAL CATALOGNUMBER ISRC ENCODEDBY TRACKNUMBER TOTALTRACKS. Except for "ENCODEDBY" they are all taken from the CUE. No further tags are added because those are the only ones which are actually physically stored on audio CDs and EAC is not good at retrieving the rest of the tags from the Internet. We strongly recommend MusicBrainz Picard for tagging the FLACs, it a perfect tagging software for being combined with perfect-flac-encode: Their website states their goal as "MusicBrainz aims to be: The ultimate source of music information by allowing anyone to contribute and releasing the data under open licenses.  [...] The universal lingua franca for music by providing a reliable and unambiguous form of music identification [...]". Seriously, give it a try, it really lives up to its promises!
* The ENCODEDBY tag contains all versions of the used tools (such as shntool and flac). If someone discovers severe bugs of the involved tools in the future you can identify affected audio files with the ENCODEDBY tag.
* The script has 5 stages of checksum verification: EAC Copy CRC vs. input WAV image CRC; AccurateRip checksums vs split singletracks' checksums; original WAV input image sha256 vs. rejoined image from singletracks sha256; sha256 of WAV singletracks vs. sha256 of decoded singletracks from FLAC singletracks. There are 5 config variables which can be used to make the script deliberately cause damage to any of the 5 stages. This can be used for making very sure that the checksum validation actually detects corruption.
* Eventually existing hidden track one audio ("HTOA") is merged with track 1 if it not longer than 1 second. If it is longer, it is kept as a separate track with number 0. This is done after AccurateRip checksum validation because AccurateRip checksums are always excluding HTOA.

# Installation:
This script was written & tested on Ubuntu 12.10 x86_64. It should work on any Ubuntu or Debian-based distribution.
To obtain its dependancies, do the following:

* Install these packages:
	* cuetools
	* flac
	* shntool
* Obtain the ["accuraterip-checksum" source code](https://github.com/leo-bogert/accuraterip-checksum) and compile it. Put the binary into a directory which is in $PATH. You need version 1.4 at least.
* Obtain the ["eac-crc" script](https://github.com/leo-bogert/eac-crc) and put it into a directory which is in $PATH. You need version 1.2 at least. Don't forget to install its required packages.
* Obtain the ["settings-exact-audio-copy" repository](https://github.com/leo-bogert/settings-exact-audio-copy). Configure Exact Audio Copy according to the file "exact-audio-copy-configuration.txt". If you do not configure EAC according to these instructions, it is STRONGLY recommended that you specify your own configuration in the "exact-audio-copy-configuration.txt". If in the future someone finds out that a certain setting causes bad quality, you can check whether the affected setting was used for this copy. I also strongly recommend that you configure EAC according to the specification from the given repository instead of inventing your own one. A lot of effort was spent on making sure that the settings are optimal for best quality. It is also notable that the default settings of EAC are not very good.

# Input:
As input, you must provide a set of 4 files with the extensions CUE/LOG/TXT/WAV (in lowercase) and the same basename. The CUE/LOG/WAV must be the output of the EAC "Test & copy image" mode. The TXT file shall contain a specification of how your EAC was configured when doing the rip. Typically, the "exact-audio-copy-configuration.txt" which was mentioned under "Installation" should be copied to be the TXT file in the input for each rip.

# Syntax:
EAC commandline should be

    perfect-flac-encode.sh "(base filename of cue/log/txt/wav)" "(path where the cue/log/txt/wav are)" "(output directory)" 

Parameter 1 is called the "release name". It must be the basename of the CUE/LOG/TXT/WAV - this is the filename without file extension.

Parameter 2 is called the "input directory". It is the directory where the input CUE/LOG/TXT/WAV are.

Parameter 3 is called the "output directory". A subdirectory with the release name as directory name will be created within it. All output will be put into this subdirectory.

# Return value:
The script will exit with exit code 0 upon success and exit code > 0 upon failure.

# Output:
Please make sure you know the parameters and their names from the Syntax section before reading on.

Upon success, the script will create a subdirectory in the output directory which is named with the release name.
This directory will contain:

* Per-track FLACs called "Track (tracknumber).flac". The titles of the tracks are NOT taken from the CUE because EAC will use the local charset of your computer when creating a CUE so it is impossible to properly parse the text-content of it. And we suggest tagging the files with MusicBrainz Picard anyway - it is able to rename them after tagging.
* A "README.txt". It tries to explain in layman's terms how the rip was created, which software was used, that the rip should be high quality, which files are in the directory, and how to restore an identical CD.
* A subdirectory called "Proof of Quality" with the following files:
	* A file "Exact Audio Copy Settings.txt" which is a copy of the original "(release name).txt". It shall contain a full specification of how you configured EAC when doing the ripping. If in the future someone finds out that a certain setting causes bad quality, you can check whether the affected setting was used for this copy.
	* A file "Exact Audio Copy.cue" which is a copy of the original "(release name).cue". It is renamed to so you do not have to fix the name after running the album through MusicBrainz Picard. Timestamps, permissions, etc. are preserved.
	* A file "Exact Audio Copy.log" which is a copy of the original "(release name).log". Timestamps, permissions, etc. are preserved.
	* A file "Exact Audio Copy.sha256" with the checksum of the original input WAV image (see the "Description" section for the purpose of this).
	* A "Perfect-FLAC-Encode.log" which contains detailled information about the encoding and verification process.

Upon success, all temporary directories will be deleted, so the output directory will be the only output.
Upon failure, the output subdirectory and the temporary directories within will NOT be deleted. If you run the script again, it will detect the existence of the output subdirectory and ask you whether it should delete it.

# Temporary Output (deleted upon success):
    Stage1_WAV_Singletracks_From_WAV_Image
These splitfiles are created using shntool from the CUE. They are the input to FLAC.
	
    Stage2_WAV_Image_Joined_From_WAV_Singletracks
For validating whether the splitfiles are correct, they are re-joined to a WAV image in this directory using shntool.
The checksum of this image is compared to the checksum of your original image.

    Stage3_FLAC_Singletracks_Encoded_From_WAV_Singletracks
This will be the actual output FLACs of the script upon success.

    Stage4_WAV_Singletracks_Decoded_From_FLAC_Singletracks
To check whether the FLACs can be decoded correctly, they are decoded into this directory.
The checksums are compared to the checksums of stage 1.

# Author:
[Leo Bogert](http://leo.bogert.de)

# Version:
1

# Donations:
[bitcoin:1PZBKLBFnbBA5h1HdKF8PATk3JnAND91yp](bitcoin:1PZBKLBFnbBA5h1HdKF8PATk3JnAND91yp)
	
# License:
GPLv3
