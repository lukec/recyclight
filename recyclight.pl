#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use LWP::UserAgent;
use JSON;
use DateTime;
use Graphics::Color::RGB;
use YAML qw/LoadFile/;
use Getopt::Long;
use Lazy::Lockfile;

$| = 1; # turn on autoflush for quicker logging

my %opts;
GetOptions(\%opts,
    'light-test', # test mode, will toggle the lights regardless of day
    'breathe',
    'test-hsl=s',
    'turn-off',
) or usage();

sub usage {
    die <<EOT;
USAGE: $0 [--light-test] [--breathe]

    Reads a config file from \$RECYCLIGHT_CONFIG_FILE or ~/.recyclight.yaml or /etc/recyclight.yaml

    --light-test   	will start changing the lights as if it was your collection day
    --breathe 	   	will pulsate the light in a breathing pattern. Useful for debugging.
    --test-hsl=H,S,L	will set the light to the given HSL (for testing)
    --turn-off		turn the light off, then exit.

EOT
}

 
my $lockfile = Lazy::Lockfile->new();
unless ($lockfile) {
    say "Couldn't get lock file. Exiting.";
    exit -1;
}

# Load our config file
my $Cfg = LoadConfig();
my $UA = LWP::UserAgent->new;

my $bridge_ip  = cfg_val('bridge_ip');
my $username   = cfg_val('bridge_user');
my $light      = cfg_val('light');
my $Lights_URL = "http://$bridge_ip/api/$username/lights/$light/state";

if ($opts{breathe}) {
    light_breathe();
    exit 0;
}
elsif ($opts{'turn-off'}) {
    turn_off_light();
    exit 0;
}

if (my $hsl = $opts{'test-hsl'}) {
    set_hsl($hsl);
    exit 0;
}

Show_boot_sequence();

while (1) {
    # Check for collection day, and turn on lights if necessary until it's
    # time to rest again.
    Recyclight();

    # Wait and then check again in a bit.
    say "Sleeping for 15 minutes";
    sleep 15 * 60;
}
exit;

    
sub Recyclight {
    # Fetch the list of upcoming events for our location.
    my $events = LoadEvents(cfg_val('ical_url'));

    # Do some date-time math to determine what timeframe we care about
    my $timezone = cfg_val('timezone');
    my $now = DateTime->now->set_time_zone($timezone);
    my $start_hour = cfg_val('start_hour'); # day before
    my $end_hour   = cfg_val('end_hour');   # day of
    say "It is currently: $now ($timezone)";
    say "Looking for events to display between $start_hour and $end_hour";

    # Loop through each event, and find the first one that we should alert
    # about.  Each event may have multiple "flags" such as garbage or
    # recycling.
    for my $evt (@{ $events->{events} }) {
        unless ($evt->{flags} and @{ $evt->{flags} }) {
            say "Skipping event on $evt->{day} - no event flags";
            next;
        }

        my $ymd = $evt->{day};
        my ($y, $m, $d) = split '-', $ymd;
        my $evt_dt = DateTime->new(
            year => $y, month => $m, day => $d, 
            time_zone => $timezone,
        );

        my $alert_start = $evt_dt->clone->subtract(days => 1)
                                        ->set_hour($start_hour);
        my $alert_end   = $evt_dt->clone->set_hour($end_hour);
        say "Event on $ymd should alert from $alert_start to $alert_end";

        # Check if it's time for us to start turning the lights on
        if ($opts{'light-test'} or ($alert_start < $now and $alert_end > $now)) {

            # Testing mode
            if ($opts{'light-test'}) {
                $alert_end = $now->clone->add(days => 1);
            }

            say "#### It's time to alert on $ymd ###";
            alert_event_until($evt, $alert_end);
            last;
        }
    }
    turn_off_light();
}


# Purpose: Toggle the lights according to the event colors until the end time
# has passed.
sub alert_event_until {
    my $evt = shift;
    my $end_time = shift;


    # First, lets figure out what colors to show.  Usually ReCollect will
    # provide colors for each event flag.  It is possible to override these
    # colors in your config file.  See the example config file for more info.
    my @colors;
    for my $f (@{ $evt->{flags} }) {
        my $rgb = $f->{color} // '#FFFFFF';
        my $name = $f->{name} // 'unknown';

        my $color = Graphics::Color::RGB->from_hex_string($rgb);
        my $hsl = $color->to_hsl;

        say "Found event flag $name: $rgb => " . $hsl->as_string;
        my $color_hash = {
            name => $name,
            rgb  => $rgb,
            hue  => $hsl->hue,
            sat  => $hsl->saturation,
            bri  => $hsl->lightness,
        };

        # Look for color overrides in the config file
        if (my $o = $Cfg->{override}{$name}) {
            say "Found color override for '$name'";
            for my $field (qw/hue sat bri/) {
                next unless $o->{$field};
                $color_hash->{$field} = $o->{$field};
                say "Setting $name field $field = $o->{$field}";
            }
        }
        else {
            say "No color overrides found for '$name'. Using default color: $rgb";
        }
        push @colors, $color_hash;
    }

    # Now we will keep flipping between the colors until it's time to turn the
    # light off!  The time interval can be changed in your config file.
    my $color_count = @colors;
    my $i = 0;
    my $color_switch_delay = cfg_val('color_switch_delay');
    while (DateTime->now < $end_time) {
        my $c = $colors[$i++ % $color_count];
	show_color($c);

        # Now sleep for a bit
        sleep $color_switch_delay;
    }

    # Finally turn off the light
    turn_off_light();
}

sub light_breathe {
    turn_on_light();
    reset_light();
    while (1) {
	print "Breathing ...\n";
        $UA->put( $Lights_URL => Content => JSON->new->encode({ alert => 'lselect' }) );
	sleep 1;
    }
}

sub set_hsl {
    reset_light();
    my $hsl = shift;
    my ($h, $s, $b) = split ',', $hsl;
    print "Setting to hue=$h sat=$s lum=$b\n";
    show_color({hue => $h, sat => $s, bri => $b});
}


# Load the config file from the first place we find it.
sub LoadConfig {
    my @files = 
        grep { -e }
        grep { defined } (
            $ENV{RECYCLIGHT_CONFIG_FILE},
            "$ENV{HOME}/.recyclight.yaml",
            "/etc/recyclight.yaml"
        );
    return LoadFile($files[0]) if @files;
    
    say "No config file could be found.  Please add ~/.recyclight.yaml or /etc/recyclight.yaml";
    say "Or you can define the RECYCLIGHT_CONFIG_FILE environment variable with the path to your file.";
    say "See the example recyclight.yaml in the project directory.";
    exit -1;
}

# Load a config key, or die if it is not found.
sub cfg_val {
    my $key = shift;
    return $Cfg->{$key}
        // die "Config key: '$key' is not defined.  "
             . "Please update your configuration file.\n";
}


# Given a ReCollect iCal feed, use the ReCollect API to fetch upcoming events.
# This will only work with the ReCollect API.
sub LoadEvents {
    my $url = shift;

    # Change the iCal URL into the JSON API endpoint, so that we get more
    # detailed and structured data for this calendar.
    unless ($url =~ s/\.[\w-]+\.ics.*//) {
        die "Couldn't change feed URL to become events JSON endpoint: $url\n";
    }

    # Now fetch the JSON content of upcoming events
    my $resp = $UA->get($url);
    unless ($resp->is_success) {
        die "Couldn't fetch feed ($url): " . $resp->status_line;
    }
    my $raw_json = $resp->content;
    return JSON->new->utf8(1)->decode($raw_json);
}


# Turn the lights on in a simple boot sequence to know that the system is working
# when this script runs.
sub Show_boot_sequence {
    turn_on_light();
    reset_light();
    my @colors = ("FF0000", "00FF00", "0000FF");
    for my $c (@colors) {
	say "  +=> Boot sequence: $c";
        my $hsl = Graphics::Color::RGB->from_hex_string($c)->to_hsl;
        my $c = {
            hue  => $hsl->hue,
            sat  => $hsl->saturation,
            bri  => 254,
        };
	show_color($c);
	sleep 2;
    }
}

sub show_color {
    my $c = shift;

    my %data = (
	hue => int($c->{hue} / 360 * 65534),
	sat => int($c->{sat} * 254),
	bri => int($c->{bri} * 254),
	transitiontime => 2,
    );

    # Tell the Hue bulb to switch to the new color.
    my $color_json = JSON->new->encode(\%data);
    say "Requesting PUT $Lights_URL $color_json";
    my $resp = $UA->put(
	$Lights_URL,
	Content => $color_json,
    );
    say $resp->status_line;
}

sub turn_on_light {
    say "Turning on light";
    $UA->put( $Lights_URL => Content => JSON->new->encode({ on => JSON::true }) );
}

sub turn_off_light {
    say "Turning off light";
    $UA->put( $Lights_URL => Content => JSON->new->encode({ on => JSON::false }) );
    reset_light();
}

sub reset_light {
    $UA->put( $Lights_URL => Content => JSON->new->encode({ alert => 'none' }) );
}
