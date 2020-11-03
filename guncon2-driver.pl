#!/usr/bin/perl

# This file was last altered on December 12, 2006, apart from the comments I am adding here November 3, 2020.

# What you see below was my first effort at implementing a GunCon2 driver in perl.  It was a flawed effort:
# It relied on FreeBSD's ugen driver to provide read access to the USB device, something I later learned
# other Unix-like OS' did not provide.  Since I couldn't (or couldn't figure out how to) write an actual
# device driver, I used perl's X11::GUITest to move the mouse and click buttons.  I had later intended 
# to find an OS-agnostic GUI control library to handle this, but it served my purposes at the time, and it
# it did indeed work.
#
# There's no argument handling here, no event-driven OO code.  Not bitwise data handling (convert to ascii).
# Not a care in the world given for good code structure.  It was just me, hacking away at it to get it to work.
# That I did.  I learned a ton about hardware hacking in the process.  I've grown a ton since then, and I
# even revisited this at one point using Java's libusb implementation to do the reads and tried to provide
# an SDL mouse, but I am afraid that code may be lost to time.
#
# So here you have it.  What I did in 2008 to get it done.  Don't expect this code to be good.  Don't expect
# it to be right.  Just use it for historical documentation, or a jumping-off point to do it right.

use Term::Cap;
use X11::GUITest qw/
	GetScreenRes
	ClickMouseButton
	MoveMouseAbs
/;

# What is the character device for the gun?
$guncon = '/dev/ugen0.1';

# Is this an original GunCon2 with the rolling x problem?
# 0 is no, 1 is yes.  Defaults to no.
$rollingx = 0;

# clearing out our status...just in case.
$report = undef;
$value = undef;
$tempvalue = undef;

# What Screen Resolution are we operating at right now?
($x, $y) = GetScreenRes();

# These are my hacks for threshold values.  A proper calibration routine 
# will have to replace this. Place 0 is the multiplier, place 1 is the 
# value.  This should all really be moved off into an rc file...
$gunxmin[0] = 0;
$gunxmin[1] = 160;
$gunymin[0] = 0;
$gunymin[1] = 1;
$gunxmax[0] = 2;
$gunxmax[1] = 232;
$gunymax[0] = 0;
$gunymax[1] = 212;


# Determine the min-max range of the gun.  We have to calculate this
# including our "multiplier" bytes.  Y-Mult almost never gets used, but
# we give it the same treatment...just in case.
$gunxrange = (($gunxmax[0] * 256) + $gunxmax[1]) - (($gunxmin[0] * 256) + $gunxmin[1]);
$gunyrange = (($gunymax[0] * 256) + $gunymax[1]) - (($gunymin[0] * 256) + $gunymin[1]);

# Find our X-Axis and Y-Axis scaling factors.
$xscale = $x / $gunxrange;
$yscale = $y / $gunyrange;

# Create our status hash for individual bits:
$status{ 'Up'} = 1;
$status{ 'Down'} = 1;
$status{ 'Left'} = 1;
$status{ 'Right'} = 1;
$status{ 'A'} = 1;
$status{ 'B'} = 1;
$status{ 'C'} = 1;
$status{ 'Trigger'} = 1;
$status{ 'Select'} = 1;
$status{ 'Start'} = 1;
$status{ 'X' } = 0;
$status{ 'X-Mult' } = 0;
$status{ 'Y' } = 0;
$status{ 'Y-Mult' } = 0;

# Check to make sure this is a character device AND that
# you actually have permission to read from it.
if (!-c $guncon) {
	print "$guncon is not a character device!\n";
	exit;
}
if (!-r $guncon) {
	print "$guncon exists, but you aren't allowed to read it!\n";
	exit;
}

# See if we can figure out what your terminal speed is...
# We'll presume 9600bps if nothing else.  This is so that
# we can refresh your display correctly.
$OSPEED = 9600;
eval {
    require POSIX;
    my $termios = POSIX::Termios->new();
    $termios->getattr;
    $OSPEED = $termios->getospeed;
};
$terminal = Term::Cap->Tgetent({OSPEED=>$OSPEED});
$clear = $terminal->Tputs('cl');


# Try to open a filehandle to the gun character device.
print "Attempting to open gun at $guncon...\n";
open GUN, $guncon or die "Can't open $guncon : $!\n";

print "$guncon opened successfully.  Proceeding to read...\n";

# Switch us to binary mode Scotty!  Read the status and print it.
binmode GUN;

while(1){
	# Determines whether we're firing this time or not.
	$fire = 0;

	# Read in 6 bytes, which is precisely the length of the
	# GunCon2's updates.  Probably could just use read and 
	# not sysread here, but I was getting some funky behavior
	# before.
	sysread(GUN,$report, 6);

	# $i is just a counter to keep track of what byte we're on.
	$i=0;

	# More paranoia to make sure we have a clean slate to work from.
	$value=undef
	$tempvalue=undef;

	# Our bytes are split and handled individually...
	foreach $value(split(//, $report)) {

		# If this is one of the button bytes, use binary, 
		# otherwise use decimal.
		if($i >= 2){
			$tempvalue = sprintf("%04d ", ord($value));
		}
		else{
			$tempvalue = sprintf("%08b ", ord($value));
		}	
		
		# Work with the buttons on the first byte.
		if($i == 0){
			@digits = split(undef,$tempvalue);
			$tempvalue = "";
			$status{'Left'} = $digits[0];
			$status{'Down'} = $digits[1];
			$status{'Right'} = $digits[2];
			$status{'Up'} = $digits[3];
			$status{'A'} = $digits[4];
			$status{'B'} = $digits[5];
			$status{'C'} = $digits[6];
			# We skip the 8th bit, as it doesn't actually
			# do anything...
		}

		# And then the buttons on the second byte.
		if($i == 1){
			@digits = split(undef,$tempvalue);
			$tempvalue = "";
			$status{'Start'} = $digits[0];
			$status{'Select'} = $digits[1];
			$status{'Trigger'} = $digits[2];
			# The rest of the bits on this byte are ignored.
		}

		if ($i == 2){
			$status{'X'} = $tempvalue;
		}
		if ($i == 3){
			$status{'X-Mult'} = $tempvalue;
		}
		if ($i == 4){
			$status{'Y'} = $tempvalue;
		}

		if ($i == 5){
			$status{'Y-Mult'} = $tempvalue;
		}


	# Increment our byte counter.
	$i++;
	}


	print "Buttons:\t";
	foreach(keys %status) {
		if ($status{$_} == 0){
			if ( !/X/g && !/Y/g) {
				print "$_ ";
			}
		}
	}

	#calibration hack


	# We have to be careful with the X-Axis due to the stupid 
	# rolling X problem.  The problem is due to the fact that some 
	# guns, namely the first-party Namco GunCon2 gets put into 100Hz 
	# mode instead of 60Hz mode.  As a result we need to check to 
	# see if the user has specified the gun has rolling x.  If they 
	# have, we have to compensate for that before continuing to 
	# scale our output based on the current screen resolution.
	if ($rollingx ==  1) {
		$status{'X'} = &unrollx($status{'X'},$status{'X-Mult'});
		$status{'X-Mult'} = 0;
	}
	$status{'X'} = $status{'X'} + ($status{'X-Mult'} * 256 );
	$status{'X'} = $status{'X'} - $gunxmin[1];
	$status{'X'} = $status{'X'} * $xscale;
	$status{'X'} = &round($status{'X'});


	# We get our actual y postion by taking the 
	# gun's return, $status{'Y'} then adding $status{'Y-Mult'}*256, 
	# then subtracting $gunymin[1], and then multiplying by $yscale.
	$status{'Y'} = $status{'Y'} + ($status{'Y-Mult'} * 256 );
	$status{'Y'} = $status{'Y'} - $gunymin[1];
	$status{'Y'} = $status{'Y'} * $yscale;
	$status{'Y'} = &round($status{'Y'});

	print "\n";
	print "X-Axis:\t$status{'X'}\n";
	print "X-Mult:\t$status{'X-Mult'}\n";
	print "Y-Axis:\t$status{'Y'}\n";
	print "Y-Mult:\t$status{'Y-Mult'}\n";
	print "Current X resolution:\t$x\n";
	print "Current Y resolution:\t$y\n";
	print "Gun\'s Y-Axis Min:\t$gunymin[1]\n";
	print "Gun\'s Y-Axis Max:\t$gunymax[1]\n";
	print "Gun\'s Y-Axis range:\t$gunyrange\n";
	print "X-Axis Scale:\t$xscale\n";
	print "Y-Axis Scale:\t$yscale\n";
	print "\n";


		if($fire >= 1){

			# If we got both X and Y coordinates, move the mouse.



			# Commented out multiplier processing...for now.
			#if($xmult >= 1){
			#	$xpos=$xpos+($xmult*256);
			#}
			#if($ymult){
			#	$xpos=$xpos*$xmult;
			#}

			print"X-Pos:\t$xpos\n";
			print"Y-Pos:\t$ypos\n";


			MoveMouseAbs $xpos , $ypos;
			ClickMouseButton(1);
			
		}

	print "\nPress Ctrl-C to exit\n";
	print $clear;

	# Clean the slate for the next update.	
	$report = undef;
	$value = undef;
	$tempvalue=undef;

}

sub round {
	my($number) = shift;
	return int($number + .5 * ($number <=> 0));
}

sub unrollx {
	# Here I will eventually implement a route that will return
	# a good value for the guns that have the rolling X problem.
	# For now just spit back what you were given and move on.
	my(@xres) = shift;
	return int(@xres);
}
