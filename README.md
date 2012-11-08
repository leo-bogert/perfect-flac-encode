perfect-flac-encode
===================

# Description:
This is an encoder script for EAC "Test & copy image" mode.
It splits the WAV image to WAV singletracks according to the EAC CUE and encodes them to FLACs.
Its primary goal is to produce perfect FLAC files by verifying checksums in all steps and being totally paranoid.
For guaranteeing this, it does the following checks and aborts if any of them fails:

* It checks the EAC LOG to make sure that AccurateRip reported a flawless rip.
* It checks whether the Test and Copy CRC in the EAC LOG match.
* It computes the EAC CRC of the input WAV image and checks whether it matches the Copy CRC in the EAC LOG.
* It computes the AccurateRip checksums of the splitfiles which it has created and compares them with the ones from the EAC LOG.
* It re-joins the singletrack files to an image and compares the checksum with the checksum of the original image from EAC to make sure that it would be possible to burn an identical CD again.
* It encodes the singletracks to FLAC with very carefully chosen settings. The full manpage of FLAC was read by me when chosing the settings.
* It runs flac --test on each singletrack which makes FLAC test the integrity of the file.
* It decodes each singletrack to WAV again and compares the checksums with the checksums of the original WAV splitfiles.

The secondary goal is providing a perfect backup of the original disc. For serving this purpose, it is ensured that it is technically possible to burn a disc of which every bit is identical to the original one. This is guaranteed by:

* Copying the original CUE/LOG to the output directory. The CUE is needed for burning the disc. The LOG serves as a proof of quality.
* A .sha256 file is generated which contains the SHA256-checksum of the original WAV image. For being able to burn a bit-identical CD, the user will have to decode the FLACs to WAVs and re-join the WAVs to an image. For making sure that this produced an image which is identical to the original one, the SHA256-checksum can be used. Notice that the CRC from the EAC LOG is not suitable for this because it is a "custom" CRC which is not computed upon the full WAV file. The EAC CRC does guarantee integrity of the audio data but is not easy to verify with standard tools.
* (NOT IMPLEMENTED YET) A "REAMDE.txt" which contains all steps necessary to restore the original WAV image is written to the output directory.

Additional features are:

* The following tags are added to the FLACs: TRACKTOTAL CATALOGNUMBER ISRC ENCODEDBY TRACKNUMBER COMMENT TOTALTRACKS. Except for "ENCODEDBY" they are all taken from the CUE. No further tags are added because those are the only ones which are actually physically stored on audio CDs and EAC is not good at retrieving the rest of the tags from the Internet. We strongly recommend MusicBrainz Picard for tagging the FLACs, it a perfect tagging software for being combined with perfect-flac-encode: Their website states their goal as "MusicBrainz aims to be: The ultimate source of music information by allowing anyone to contribute and releasing the data under open licenses.  [...] The universal lingua franca for music by providing a reliable and unambiguous form of music identification [...]". Seriously, give it a try, it really lives up to its promises!
* The script has 5 stages of checksum verification: EAC Copy CRC vs. input WAV image CRC; AccurateRip checksums vs split singletracks' checksums; original WAV input image sha256 vs. rejoined image from singletracks sha256; sha256 of WAV singletracks vs. sha256 of decoded singletracks from FLAC singletracks. There are 5 config variables which can be used to make the script deliberately cause damage to any of the 5 stages. This can be used for making very sure that the checksum validation actually detects corruption.


# Installation:
This script was written & tested on Ubuntu 12.04 x86_64. It should work on any Ubuntu or Debian-based distribution.
To obtain its dependancies, do the following:

* Install these packages:
	* cuetools
	* flac
	* shntool
* Obtain the ["accuraterip-checksum" binary](https://github.com/leo-bogert/accuraterip-checksum/downloads) (or compile it on your own) and put it into your home directory.
* Obtain the ["eac-crc" script](https://github.com/leo-bogert/eac-crc) and put it into your home directory. Don't forget to install its required packages.


# Syntax:
EAC commandline should be

    perfect-flac-encode.sh "(path where the wav/log/cue are)" "%albumartist% - %albumtitle%"

The WAV / CUE / LOG files must have the name "%albumartist% - %albumtitle%.(wav/cue/log)".
The output of the script will be in a subdirectory whose name is equal to "%albumartist% - %albumtitle%".

# Return value:
The script will exit with exit code 0 upon success and exit code > 0 upon failure.

# Output:
As you know from the syntax, parameter 1 is the "working directory".
Parameter 2 is the filename of wav/cue/log and called "album name".

Upon success, the script will create a subdirectory in the working directory which is named with the album name - the output directory.
The output directory will contain:

* Per-track FLACs called "(tracknumber) - (track title).flac"
* A copy of the origianl "(album name).log" and "(album name).cue" (with timestamps, permissions, etc. preserved)
* A file "(album name).sha256" with the checksum of the original input WAV image (see the "Description" section for the purpose of this)

Upon success, all temporary directories will be deleted, so the output directory will be the only output.
Upon failure, neither the temporary files nor the output is deleted. If you run the script again, it will detect the existence of temp/output directories and ask you whether it should delete them.

# Temporary Output (deleted upon success):
    Stage1_WAV_Singletracks_From_WAV_Image
These splitfiles are created using shntool from the CUE. They are the input to FLAC
	
    Stage2_WAV_Image_Joined_From_WAV_Singletracks
For validating whether the splitfiles are correct, they are re-joined to a WAV image in this directory using shntool.
The checkput of this image is compared to the checksum of your original image.

    Stage3_FLAC_Singletracks_Encoded_From_WAV_Singletracks
This is the actual output of the script which you want to add to your library.

    Stage4_WAV_Singletracks_Decoded_From_FLAC_Singletracks
To check whether the FLACs can be decoded correctly, they are decoded into this directory.
The checksums are compared to the checksums of Stage1.

# Author:
[Leo Bogert](http://leo.bogert.de)

# Version:
BETA8 - NOT for productive use!

# Donations:
[bitcoin:1PZBKLBFnbBA5h1HdKF8PATk3JnAND91yp](bitcoin:1PZBKLBFnbBA5h1HdKF8PATk3JnAND91yp)
	
# License:
GPLv3