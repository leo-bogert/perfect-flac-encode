perfect-flac-encode
===================

# Description:
	This is an encoder script for EAC "Test & copy image" mode. It splits the  WAV image to WAV singletracks and encodes them to flacs.
	Its goal is to produce perfect FLAC files by verifying checksums in all steps. For guaranteeing this, it does the following:
	- It checks the EAC log file to make sure that AccurateRip reported a flawless rip
	- It computes the AccurateRip checksums of the splitfiles which it has created and compares them with the ones from the EAC logfile
	- It re-joins the singletrack files to an image and compares the checksum with the checksum of the original image from EAC to make sure that it would be possible to burn an identical CD again.
	- It encodes the singletracks to FLAC with very carefully chosen settings.
	- It runs flac --test on each singletrack which makes FLAC test the integrity of the file.
	- It decodes each singletrack to WAV again and compares their checksums with the checksums of the original WAV splitfiles.

# Installation:
	This script was written & tested on Ubuntu 12.04 x86_64. It should work on any Ubuntu or Debian-based distribution.
	To obtain its dependancies, do the following:
	- Install these packages:
		flac
		shntool
	- Obtain the "accuraterip-checksum" binary (or compile it on your own): https://github.com/leo-bogert/accuraterip-checksum/downloads
	  Put the binary into your home directory.

# Syntax:
	EAC commandline should be (EAC variables taken from http://www.exactaudiocopy.de/en/index.php/support/faq/compression-questions/): 
	encode.sh "<path where the wav/log/cue are>" "%albumartist% - %albumtitle%"

# Author:
	Leo Bogert (http://leo.bogert.de)

# Version:
	BETA1 - NOT for productive use!

# Donations:
	bitcoin:1PZBKLBFnbBA5h1HdKF8PATk3JnAND91yp
	
# License:
	GPLv3