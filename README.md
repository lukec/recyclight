# Recyclight

Control a Philips Hue light based on your city's garbage and recycling days.


# Pre-Reqs

1. This amazing hack only works with cities or counties that use [ReCollect](https://recollect.net) for their solid waste communications.

1. This script will control a Philips Hue lightbulb using a Philips Hue bridge, so you must have those setup and working before starting this project.

1. This script must have network access to your Philips Hue Bridge.  You could run it on a raspberry pi or other computer in your house.


# Philips Hue Set-up

1. Activate your Philips Hue Color bulb and connect it to your Hue Bridge like normal.

1. Find the IP address of your Hue Bridge https://www.developers.meethue.com/documentation/hue-bridge-discovery

2. Get an access token to the hue bridge. They call it a `username`:

> `curl -s -X POST -H 'Content-Type: application/json' -d '{"devicetype":"awesome#recyclight"}' http://YOUR_BRIDGE_IP/api`

This will return some JSON with a `username` field, which we will use below.

3. Now fetch the list of lights from the bridge:

> `curl http://YOUR_BRIDGE_IP/api/YOUR_USERNAME/lights | python -m json.tool`

This will show you all the lights connected to your bridge.  You can pick the one you want to control.


# Software Setup

1. Create a config file. Copy the `recyclight.example.yaml` file.

Place your file in `~/.recyclight.yaml`, `/etc/recyclight.yaml` or in another location and use the `RECYCLIGHT_CONFIG_FILE` environment variable.

4. Install the necessary Perl dependencies 

The `cpanfile` lists the dependencies.  The `cpanm` tool can make installing dependencies very easy. Check it out.

5. Try it out!

Try running the script.  The output is fairly verbose.  For testing purposes it can help to use different ical feeds, based on different addresses that may or may not have collection in progress.


# Light Fixtures

You can use any light you want, as long as it's connected to your bridge.  It could be in your house, on your garage or in your alley for your neighbours.

