perfect-flac-encode
===================

*Description:*
	This is an encoder script for EAC "Test & copy image" mode.
	It splits the WAV image to WAV singletracks according to the EAC CUE and encodes them to FLACs.
	Its goal is to produce perfect FLAC files by verifying checksums in all steps and being totally paranoid.
	For guaranteeing this, it does the following checks and aborts if any of them fails:
	- It checks the EAC LOG to make sure that AccurateRip reported a flawless rip.
	- It computes the AccurateRip checksums of the splitfiles which it has created and compares them with the ones from the EAC LOG.
	- It re-joins the singletrack files to an image and compares the checksum with the checksum of the original image from EAC to make sure that it would be possible to burn an identical CD again.
	- It encodes the singletracks to FLAC with very carefully chosen settings. The full manpage of FLAC was read by me when chosing the settings.
	- It runs flac --test on each singletrack which makes FLAC test the integrity of the file.
	- It decodes each singletrack to WAV again and compares the checksums with the checksums of the original WAV splitfiles.

	Additional features are:	
	- The script has 4 stages of output: Split singletracks, rejoined image from singletracks, encoded FLAC from singletracks, decoded FLAC to singletracks again.
	  There are 4 config variables which can be used to make the script deliberately cause damage to any of the 4 stages.
	  This can be used for making very sure that the checksum validation actually detects corruption.

*Installation:*
	This script was written & tested on Ubuntu 12.04 x86_64. It should work on any Ubuntu or Debian-based distribution.
	To obtain its dependancies, do the following:
	- Install these packages:
		flac
		shntool
	- Obtain the "accuraterip-checksum" binary (or compile it on your own): https://github.com/leo-bogert/accuraterip-checksum/downloads
	  Put the binary into your home directory.

*Syntax:*
	EAC commandline should be (EAC variables taken from http://www.exactaudiocopy.de/en/index.php/support/faq/compression-questions/): 
	encode.sh "<path where the wav/log/cue are>" "%albumartist% - %albumtitle%"

	The WAV / CUE / LOG files must have the name "%albumartist% - %albumtitle%.[wav/cue/log]".
	
*Output:*
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
	
*Author:*
	Leo Bogert (http://leo.bogert.de)

*Version:*
	BETA2 - NOT for productive use!

*Donations:*
	bitcoin:1PZBKLBFnbBA5h1HdKF8PATk3JnAND91yp
	
*License:*
	GPLv3