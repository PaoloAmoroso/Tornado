var (width, height) = (512, 512);

var FALSE = 0;
var TRUE = 1;

var mycanvas = nil;
var root = nil;
var setupCanvas = func {
	mycanvas = canvas.new({
	  "name": "MM",
	  "size": [height, height],
	  "view": [height, height],
	  "mipmapping": 0,
	  #"additive-blend": 1
	});
	root = mycanvas.createGroup();
	root.set("font", "LiberationFonts/LiberationMono-Regular.ttf");
	mycanvas.setColorBackground(0, 0, 0, 1.0);
	mycanvas.addPlacement({"node": "RPMD.screen"});
	mycanvas.addPlacement({"node": "CRPMD.screen"});
}
var (center_x, center_y) = (width/2,height/2);

var MM2TEX = 1;
var texel_per_degree = 2*MM2TEX;
var KT2KMH = 1.85184;

# map setup

var tile_size = 256;

var type = "light_nolabels";

# index   = zoom level
# content = meter per pixel of tiles
#                   0                             5                               10                               15                      19
var meterPerPixel = [156412,78206,39103,19551,9776,4888,2444,1222,610.984,305.492,152.746,76.373,38.187,19.093,9.547,4.773,2.387,1.193,0.596,0.298];# at equator
#zooms      = [4, 7, 9, 11, 13];#old
var zooms      = [10, 11];
var zoomLevels = [100, 50];
var zoom_curr  = 0;
var zoom = zooms[zoom_curr];

var M2TEX = 1/(meterPerPixel[zoom]*math.cos(getprop('/position/latitude-deg')*D2R));

var toggleScale = func {
  zoom_curr -= 1;
  if (zoom_curr < 0) {
  	zoom_curr = 1;
  }
  zoom = zooms[zoom_curr];
  M2TEX = 1/(meterPerPixel[zoom]*math.cos(getprop('/position/latitude-deg')*D2R));
  setprop("tornado/displays/scale", zoom_curr);
}

var maps_base = getprop("/sim/fg-home") ~ '/cache/mapsTornado';

var makeUrl =
  string.compileTemplate('https://b.tile.openstreetmap.org/{z}/{x}/{y}.png');
var makePath =
  string.compileTemplate(maps_base ~ '/stl/{z}/{x}/{y}.png');
var num_tiles = [5, 5];# must be uneven, 5x5 will ensure we never see edge of map tiles when canvas is 512px high.

var center_tile_offset = [(num_tiles[0] - 1) / 2,(num_tiles[1] - 1) / 2];#(width/tile_size)/2,(height/tile_size)/2];

##
# initialize the map by setting up
# a grid of raster images

var tiles = setsize([], num_tiles[0]);

var last_tile = [-1,-1];
var last_type = type;
var last_zoom = zoom;
var lastLiveMap = getprop("tornado/displays/live-map");
var lastDay   = TRUE;

# stuff

var brightnessP = func {
	mm.brightness += 0.25;
};

var brightnessM = func {
	mm.brightness -= 0.25;
};

var bright = 0;

#TI symbol colors
var COLOR_WHITE      = [1.00,1.00,1.00];# self
var COLOR_YELLOW     = [1.00,1.00,0.00];# possible threat LV
var COLOR_RED        = [1.00,0.00,0.00];# threat LV
var COLOR_GREEN      = [0.00,1.00,0.00];# own side LV
var COLOR_GREEN_DARK = [0.00,0.50,0.00];# RWR
var COLOR_BLUE_LIGHT = [0.65,0.65,1.00];
var COLOR_TYRK_DARK  = [0.20,0.75,0.60];# route polygon
var COLOR_TYRK       = [0.35,1.00,0.90];# navigation aids
var COLOR_GREY       = [0.50,0.50,0.50];# inactive
var COLOR_GREY_LIGHT = [0.70,0.70,0.70];
var COLOR_BLACK      = [0.00,0.00,0.00];# active
var COLOR_GREY_BLUE  = [0.60,0.60,0.85];# flight data

var COLOR_DAY   = "rgb(256,256,256)";# color fill behind map which will modulate to make it darker.
var COLOR_NIGHT = "rgb( 64, 64, 64)";

var a = 1.0;#alpha
var w = 1.0;#stroke width


var roundabout = func(x) {
  var y = x - int(x);
  return y < 0.5 ? int(x) : 1 + int(x) ;
};

var clamp = func(v, min, max) { v < min ? min : v > max ? max : v };

var circlePos = func (deg, radius) {
	return [radius*math.cos(deg*D2R),radius*math.sin(deg*D2R)];
}

var circlePosH = func (deg, radius) {
	# compensate for heading going opposite unit circle and 0 deg being forward
	return [radius*math.cos((-deg+90)*D2R),-radius*math.sin((-deg+90)*D2R)];
}

var containsVector = func (vec, item) {
	foreach(test; vec) {
		if (test == item) {
			return TRUE;
		}
	}
	return FALSE;
}

var extrapolate = func (x, x1, x2, y1, y2) {
    return y1 + ((x - x1) / (x2 - x1)) * (y2 - y1);
};

# degree
# \xc2\xb0


var MM = {

	setupCanvasSymbols: func {
		# map groups
		me.mapCentrum = root.createChild("group")
			.set("z-index", 1)
			.setTranslation(width/2,height*2/3);
		me.mapCenter = me.mapCentrum.createChild("group");
		me.mapRot = me.mapCenter.createTransform();
		me.mapFinal = me.mapCenter.createChild("group");
		#me.mapFinal.setTranslation(-tile_size*center_tile_offset[0],-tile_size*center_tile_offset[1]);

		# groups
		me.rootCenter = root.createChild("group")
			.setTranslation(width/2,height/2)
			.set("z-index",  9);
		me.rootRealCenter = root.createChild("group")
			.setTranslation(width/2,height/2)
			.set("z-index", 10);

		me.ppGrp = me.rootCenter.createChild("group")
			.set("z-index", 2);

	    # route symbols
	    me.steerpoint = [];
	    me.steerpointText = [];
	    me.steerpointSymbol = [];
	    me.steerPointMax = -1;
	    
	    me.steerPoly = me.rootCenter.createChild("group")
	    			.set("z-index", 6);
	},

	new: func {
	  	var ti = { parents: [MM] };
	  	ti.input = {
			alt_ft:               "instrumentation/altimeter/indicated-altitude-ft",
			APLockAlt:            "autopilot/locks/altitude",
			APTgtAgl:             "autopilot/settings/target-agl-ft",
			APTgtAlt:             "autopilot/settings/target-altitude-ft",
			#heading:              "instrumentation/heading-indicator/indicated-heading-deg",
			heading:              "orientation/heading-deg",
			rad_alt:              "position/altitude-agl-ft",
			radarRange:           "instrumentation/radar/range",
			radarServ:            "instrumentation/radar/serviceable",
			rmActive:             "autopilot/route-manager/active",
			rmDist:               "autopilot/route-manager/wp/dist",
			rmId:                 "autopilot/route-manager/wp/id",
			rmTrueBearing:        "autopilot/route-manager/wp/true-bearing-deg",
			RMCurrWaypoint:       "autopilot/route-manager/current-wp",
			roll:                 "instrumentation/attitude-indicator/indicated-roll-deg",
			timeElapsed:          "sim/time/elapsed-sec",
			viewNumber:           "sim/current-view/view-number",
			headTrue:             "orientation/heading-deg",
			headMagn:             "orientation/heading-magnetic-deg",
			station:          	  "controls/armament/station-select-custom",
			roll:             	  "orientation/roll-deg",
			pitch:             	  "orientation/pitch-deg",
			radar_serv:       	  "instrumentation/radar/serviceable",
	        ctrlRadar:        	  "controls/altimeter-radar",
	        nav0InRange:      	  "instrumentation/nav[0]/in-range",
	        APLockHeading:    	  "autopilot/locks/heading",
	        APTrueHeadingErr: 	  "autopilot/internal/true-heading-error-deg",
	        APnav0HeadingErr: 	  "autopilot/internal/nav1-heading-error-deg",
	        APHeadingBug:     	  "autopilot/settings/heading-bug-deg",
	        RMWaypointBearing:	  "autopilot/route-manager/wp/bearing-deg",
	        RMActive:             "autopilot/route-manager/active",
	        nav0Heading:          "instrumentation/nav[0]/heading-deg",
	        ias:                  "instrumentation/airspeed-indicator/indicated-speed-kt",
	        tas:                  "instrumentation/airspeed-indicator/true-speed-kt",
	        wow0:                 "fdm/jsbsim/gear/unit[0]/WOW",
        	wow1:                 "fdm/jsbsim/gear/unit[1]/WOW",
        	wow2:                 "fdm/jsbsim/gear/unit[2]/WOW",
        	gearsPos:         	  "gear/gear/position-norm",
        	latitude:             "position/latitude-deg",
        	longitude:            "position/longitude-deg",
			terrainWarn:          "instrumentation/terrain-warning",
            cursorControlX:       "fdm/jsbsim/fcs/cursor/cursor-control-X",
            cursorControlY:       "fdm/jsbsim/fcs/cursor/cursor-control-Y",
            cursorSelect:         "fdm/jsbsim/fcs/cursor/cursor-select",
			elevCmd:              "fdm/jsbsim/fcs/elevator-cmd-norm",
			ailCmd:               "fdm/jsbsim/fcs/aileron-cmd-norm",
			trigger:              "controls/armament/trigger",
			instrNorm:            "controls/lighting/instruments-norm",
      	};

      	foreach(var name; keys(ti.input)) {
        	ti.input[name] = props.globals.getNode(ti.input[name], 1);
      	}
      	
      	ti.setupCanvasSymbols();
      	
      	#map
      	ti.lat = ti.input.latitude.getValue();
		ti.lon = ti.input.longitude.getValue();
      	ti.mapSelfCentered = TRUE;
      	ti.day = TRUE;
      	ti.setupMap();

		# display
		ti.brightness = 1;
		ti.active = TRUE;
		ti.off = 0;
		ti.mapshowing = TRUE;

		# steerpoints
		ti.newSteerPos = nil;
		ti.showSteers = TRUE;#only for debug turn to false
		ti.showSteerPoly = TRUE;#only for debug turn to false
		
		# misc
		ti.twoHz = 0;		

      	return ti;
	},


	########################################################################################################
	########################################################################################################
	#
	#  begin main loops
	#
	#
	########################################################################################################
	########################################################################################################

	loop: func {

		if (me.brightness < 0.25) {
			me.brightness = 0.25;
		} elsif (me.brightness > 1) {
			me.brightness = 1;
		}

		if (me.off == TRUE) {
			setprop("tornado/avionics/brightness-mm", 0);
			settimer(func{me.loop();},0.5);
			return;
		} else {
			setprop("tornado/avionics/brightness-mm", me.brightness);
			#setprop("ja37/avionics/cursor-on", cursorOn);
		}
		if (me.day == TRUE) {
			mycanvas.setColorBackground(0.3, 0.3, 0.3, 1.0);
		} else {
			mycanvas.setColorBackground(0.15, 0.15, 0.15, 1.0);
		}
		me.whereIsMap();#must be before mapUpdate
		me.updateMap();
		#me.updateMapNames();
		
		me.twoHz = !me.twoHz;
		settimer(func{me.loop();},0.5);
	},

	showMap: func {
		#
		# Reveal map and its overlays
		#
		me.logPage = 0;
		me.mapCentrum.show();
		me.rootCenter.show();
		me.rootSVY.show();
		me.logRoot.hide();
		me.navBugs.show();
		me.bottom_text_grp.show();
		me.mapshowing = TRUE;
	},

	hideMap: func {
		#
		# Hide map and its overlays (due to a log page being displayed)
		#
		me.rootSVY.hide();
		me.mapCentrum.hide();
		me.rootCenter.hide();
		me.bottom_text_grp.hide();
		me.navBugs.hide();
		me.mapshowing = FALSE;
	},
	
	updateMapNames: func {
		if (me.mapPlaces == PLACES or me.menuMain == MAIN_MISSION_DATA) {
			type = "light_all";
			makePath = string.compileTemplate(maps_base ~ '/cartoLN/{z}/{x}/{y}.png');
		} else {
			type = "light_nolabels";
			makePath = string.compileTemplate(maps_base ~ '/cartoL/{z}/{x}/{y}.png');
		}
	},

  	laloToTexel: func (la, lo) {
		me.coord = geo.Coord.new();
  		me.coord.set_latlon(la, lo);
  		me.coordSelf = geo.Coord.new();#TODO: dont create this every time method is called
  		me.coordSelf.set_latlon(me.lat_own, me.lon_own);
  		me.angle = (me.coordSelf.course_to(me.coord)-me.input.headTrue.getValue())*D2R;
		me.pos_xx		 = -me.coordSelf.distance_to(me.coord)*M2TEX * math.cos(me.angle + math.pi/2);
		me.pos_yy		 = -me.coordSelf.distance_to(me.coord)*M2TEX * math.sin(me.angle + math.pi/2);
  		return [me.pos_xx, me.pos_yy];#relative to rootCenter
  	},
  	
  	laloToTexelMap: func (la, lo) {
		me.coord = geo.Coord.new();
  		me.coord.set_latlon(la, lo);
  		me.coordSelf = geo.Coord.new();#TODO: dont create this every time method is called
  		me.coordSelf.set_latlon(me.lat, me.lon);
  		me.angle = (me.coordSelf.course_to(me.coord))*D2R;
		me.pos_xx		 = -me.coordSelf.distance_to(me.coord)*M2TEX * math.cos(me.angle + math.pi/2);
		me.pos_yy		 = -me.coordSelf.distance_to(me.coord)*M2TEX * math.sin(me.angle + math.pi/2);
  		return [me.pos_xx, me.pos_yy];#relative to mapCenter
  	},

  	TexelToLaLoMap: func (x,y) {#relative to map center
  		x /= M2TEX;
  		y /= M2TEX;
  		me.mDist  = math.sqrt(x*x+y*y);
  		if (me.mDist == 0) {
  			return [me.lat, me.lon];
  		}
  		me.acosInput = clamp(x/me.mDist,-1,1);
  		if (y<0) {
  			me.texAngle = math.acos(me.acosInput);#unit circle on TI
  		} else {
  			me.texAngle = -math.acos(me.acosInput);
  		}
  		#printf("%d degs %0.1f NM", me.texAngle*R2D, me.mDist*M2NM);
  		me.texAngle  = -me.texAngle*R2D+90;#convert from unit circle to heading circle, 0=up on display
  		me.headAngle = me.input.heading.getValue()+me.texAngle;#bearing
  		#printf("%d bearing   %d rel bearing", me.headAngle, me.texAngle);
  		me.coordSelf = geo.Coord.new();#TODO: dont create this every time method is called
  		me.coordSelf.set_latlon(me.lat, me.lon);
  		me.coordSelf.apply_course_distance(me.headAngle, me.mDist);

  		return [me.coordSelf.lat(), me.coordSelf.lon()];
  	},


	########################################################################################################
	########################################################################################################
	#
	#  map display
	#
	#
	########################################################################################################
	########################################################################################################



	setupMap: func {
		me.mapFinal.removeAllChildren();
		for(var x = 0; x < num_tiles[0]; x += 1) {
		  	tiles[x] = setsize([], num_tiles[1]);
		  	for(var y = 0; y < num_tiles[1]; y += 1) {
		    	tiles[x][y] = me.mapFinal.createChild("image", "map-tile").set("z-index", 15);
		    	if (me.day == TRUE) {
		    		tiles[x][y].set("fill", COLOR_DAY);
	    		} else {
	    			tiles[x][y].set("fill", COLOR_NIGHT);
	    		}
	    	}
		}
	},

	whereIsMap: func {
		# update the map position
		me.lat_own = me.input.latitude.getValue();
		me.lon_own = me.input.longitude.getValue();
		if (1 or me.menuMain != MAIN_MISSION_DATA or me.mapSelfCentered) {
			# get current position
			me.lat = me.lat_own;
			me.lon = me.lon_own;# TODO: USE GPS/INS here.
		}
		M2TEX = 1/(meterPerPixel[zoom]*math.cos(me.lat*D2R));
	},

	updateMap: func {
		# update the map
		if (lastDay != me.day)  {
			me.setupMap();
		}
		me.rootCenterY = height-height*0.5;
		if (!me.mapSelfCentered) {
			me.lat_wp   = me.input.latitude.getValue();
			me.lon_wp   = me.input.longitude.getValue();
			me.tempReal = me.laloToTexel(me.lat,me.lon);
			me.rootCenter.setTranslation(width/2-me.tempReal[0], me.rootCenterY-me.tempReal[1]);
			#me.rootCenterTranslation = [width/2-me.tempReal[0], me.rootCenterY-me.tempReal[1]];
		} else {
			me.tempReal = [0,0];
			me.rootCenter.setTranslation(width/2, me.rootCenterY);
			#me.rootCenterTranslation = [width/2, me.rootCenterY];
		}
		me.mapCentrum.setTranslation(width/2, me.rootCenterY);

		me.n = math.pow(2, zoom);
		me.center_tile_float = [
			me.n * ((me.lon + 180) / 360),
			(1 - math.ln(math.tan(me.lat * D2R) + 1 / math.cos(me.lat * D2R)) / math.pi) / 2 * me.n
		];
		# center_tile_offset[1]
		me.center_tile_int = [int(me.center_tile_float[0]), int(me.center_tile_float[1])];

		me.center_tile_fraction_x = me.center_tile_float[0] - me.center_tile_int[0];
		me.center_tile_fraction_y = me.center_tile_float[1] - me.center_tile_int[1];
#printf("centertile: %d,%d fraction %.2f,%.2f",me.center_tile_int[0],me.center_tile_int[1],me.center_tile_fraction_x,me.center_tile_fraction_y);
		me.tile_offset = [int(num_tiles[0]/2), int(num_tiles[1]/2)];

		# 3x3 example: (same for both canvas-tiles and map-tiles)
		#  *************************
		#  * -1,-1 *  0,-1 *  1,-1 *
		#  *************************
		#  * -1, 0 *  0, 0 *  1, 0 *
		#  *************************
		#  * -1, 1 *  0, 1 *  1, 1 *
		#  *************************
		#

		for(var xxx = 0; xxx < num_tiles[0]; xxx += 1) {
			for(var yyy = 0; yyy < num_tiles[1]; yyy += 1) {
				tiles[xxx][yyy].setTranslation(-int((me.center_tile_fraction_x - xxx+me.tile_offset[0]) * tile_size), -int((me.center_tile_fraction_y - yyy+me.tile_offset[1]) * tile_size));
			}
		}

		me.liveMap = getprop("tornado/displays/live-map");
		me.zoomed = zoom != last_zoom;
		if(me.center_tile_int[0] != last_tile[0] or me.center_tile_int[1] != last_tile[1] or type != last_type or me.zoomed or me.liveMap != lastLiveMap or lastDay != me.day)  {
			for(var x = 0; x < num_tiles[0]; x += 1) {
		  		for(var y = 0; y < num_tiles[1]; y += 1) {
		  			# inside here we use 'var' instead of 'me.' due to generator function, should be able to remember it.
		  			var xx = me.center_tile_int[0] + x - me.tile_offset[0];
		  			if (xx < 0) {
		  				# when close to crossing 180 longitude meridian line, make sure we see the tiles on the positive side of the line.
		  				xx = me.n + xx;#print(xx~" from "~(xx-me.n));
		  			} elsif (xx >= me.n) {
		  				# when close to crossing 180 longitude meridian line, make sure we dont double load the tiles on the negative side of the line.
		  				xx = xx - me.n;#print(xx~" from "~(xx+me.n));
		  			}
					var pos = {
						z: zoom,
						x: xx,
						y: me.center_tile_int[1] + y - me.tile_offset[1],
						type: type
					};

					(func {# generator function
					    var img_path = makePath(pos);
					    var tile = tiles[x][y];
					    #print('showing ' ~ img_path);
					    if( io.stat(img_path) == nil and me.liveMap == TRUE) { # image not found, save in $FG_HOME
					      	var img_url = makeUrl(pos);
					      	#print('requesting ' ~ img_url);
					      	http.save(img_url, img_path)
					      		.done(func(r) {
					      	  		#print('received image ' ~ me.img_path~" " ~ r.status ~ " " ~ r.reason);
					      	  		#print(""~(io.stat(me.img_path) != nil));
					      	  		tile.set("src", img_path);# this sometimes fails with: 'Cannot find image file' if use me. instead of var.
					      	  		tile.update();
					      	  		})
					          #.done(func {print('received image ' ~ img_path); tile.set("src", img_path);})
					          .fail(func (r) {#print('Failed to get image ' ~ img_path ~ ' ' ~ r.status ~ ': ' ~ r.reason);
					          				tile.set("src", "Aircraft/Tornado/Models/Cockpit/Instruments/rpmd/emptyTile.png");
					      					tile.update();
					      					});
					    } elsif (io.stat(img_path) != nil) {# cached image found, reusing
					      	#print('loading ' ~ me.img_path);
					      	tile.set("src", img_path);
					      	tile.update();
					    } else {
					    	# internet not allowed, so noise tile shown
					    	tile.set("src", "Aircraft/Tornado/Models/Cockpit/Instruments/rpmd/noiseTile.png");
					      	tile.update();
					    }
					})();
		  		}
			}

		last_tile = me.center_tile_int;
		last_type = type;
		last_zoom = zoom;
		lastLiveMap = me.liveMap;
		lastDay = me.day;
		}

		#me.mapRot.setRotation(-me.input.heading.getValue()*D2R);
		#me.mapCenter.setRotation(-me.input.heading.getValue()*D2R);#switched to direct rotation to try and solve issue with approach line not updating fast.
		me.rootCenter.setRotation(me.input.heading.getValue()*D2R);
		#me.mapCenter.update();
	},
};

var mm = nil;
var init = func {
	removelistener(idl); # only call once
	setupCanvas();
	mm = MM.new();
	settimer(func {
		mm.loop();
	},0.5);# this will prevent it from starting before route has been initialized.
}

var idl = setlistener("sim/signals/fdm-initialized", init, nil, 1);
