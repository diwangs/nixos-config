{ config, lib, pkgs, ... }: {
	# Pipewire
	services.pipewire = {
		enable = true;
		pulse.enable = true;				# PulseAudio compatibility
		alsa.enable = true;					# ALSA compatibility
		alsa.support32Bit = true;

		extraConfig.pipewire."99-sample-rate" = {
			"context.properties" = {
				# "default.clock.rate" = 96000; # Gnome uses 48 kHz
				"default.clock.allowed-rates" = [ 
					44100		# CD-quality audio
					48000 	# Videos and GNOME
					88200 	# Hi-Res Audio (2 x 44.1 kHz)
					96000		# Hi-Res Audio (2 x 48 kHz)
					# 176400	# Hi-Res Audio (4 x 44.1 kHz) unsupported by D90
					192000	# Hi-Res Audio (4 x 48 kHz)
					# 768000	# Max DAC capability
				];
			};
			"stream.properties" = {
				"resample.quality" = 14;
			};
		};
	};
}