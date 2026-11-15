extends Node2D

const APP_NAME := "AREOGRAPH"
const APP_TAG := "Mars navigation & information system"
const CREDIT := "Designed by: Abdulrahman & Saleh"

const WORLD_Z := 7
const TILE := 256
const CENTER := Vector2(18.43, 77.41)          # world origin = Jezero landing area (lat, lon)
const CRATER_CENTER := Vector2(18.38, 77.58)
const KM_PER_DEG := 59.27
const MARS_R_KM := 3389.5
const MAX_ZOOM := 300.0
const LOCAL_ZOOM := 5.0       # Jezero operations fully visible from this zoom
const LOCAL_FADE := 2.5       # ... and start fading in here
const DETAIL_GAIN := 1.7      # brightness of CTX/HiRISE when blended over color (raise if too dark)
const LABEL_SIZE := 12

# ---- Zone circle sizing (Jezero operations) ----
const ZONE_SCALE := 0.35
const ZONE_MIN_KM := 0.25
const ZONE_GAP_KM := 0.15

# ---- Performance tuning ----
const MAX_REQUESTS := 20
const MAX_BIAS := 1
const BELOW_MIN := 3
const USE_CACHE := true
const CACHE_DIR := "user://tilecache"
const BASE_Z := 3
const PREFETCH := 1.2
const MAX_RETRIES := 3
const TILE_CAP := 650
const MAX_ADD_PER_FRAME := 3

# Palette
const ORANGE := Color(1.0, 0.42, 0.0)
const HAZ_RED := Color(0.92, 0.13, 0.10)
const GREEN := Color(0.18, 0.80, 0.40)
const BLUE := Color(0.25, 0.66, 1.0)
const GOLD := Color(1.0, 0.78, 0.15)
const VIOLET := Color(0.72, 0.52, 1.0)
const SILVER := Color(0.86, 0.86, 0.92)
const ICE := Color(0.65, 0.88, 1.0)
const DIM := Color(1, 1, 1, 0.6)
const PANEL := Color(0.20, 0.02, 0.03, 0.94)
const PANEL_DARK := Color(0.12, 0.01, 0.02, 0.96)
const BASE := "https://trek.nasa.gov/tiles/Mars/EQ/"

const SHARPEN_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 2.0) = 0.5;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec3 n = texture(screen_tex, SCREEN_UV + vec2(0.0, -px.y)).rgb;
	vec3 s = texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb;
	vec3 e = texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb;
	vec3 w = texture(screen_tex, SCREEN_UV + vec2(-px.x, 0.0)).rgb;
	COLOR = vec4(clamp(c + strength * (4.0 * c - n - s - e - w), 0.0, 1.0), 1.0);
}
"""
const SHARP_NAMES := ["Off", "Low", "Medium", "High"]
const SHARP_VALUES := [0.0, 0.25, 0.5, 0.9]

# Imagery layers (NASA Mars Trek). "mul" layers are multiplied over the color map,
# so detail imagery never leaves grey cut-out patches.
const LAYER_DEFS := [
	{"name": "Viking color (232 m)", "id": "Mars_Viking_MDIM21_ClrMosaic_global_232m", "min": 0, "max": 8, "order": 0, "adapt": true, "bias": 0, "cap": 160, "mul": false},
	{"name": "THEMIS thermal (100 m)", "id": "Mars_MO_THEMIS-IR-Day_mosaic_global_100m_v12_clon0_ly", "min": 0, "max": 9, "order": 20, "adapt": true, "bias": 0, "cap": 160, "mul": false},
	{"name": "MOLA elevation (463 m)", "id": "Mars_MGS_MOLA_ClrShade_merge_global_463m", "min": 0, "max": 8, "order": 40, "adapt": true, "bias": 0, "cap": 160, "mul": false},
	{"name": "CTX detail (5 m)", "id": "CTX_beta01_uncontrolled_5m_Caltech", "min": 8, "max": 14, "order": 100, "adapt": false, "bias": 1, "cap": 220, "mul": true},
	{"name": "HiRISE Jezero (25 cm)", "id": "JEZ_hirise_soc_006_orthoMosaic_25cm_Eqc_latTs0_lon0_first_dd", "min": 12, "max": 17, "order": 200, "adapt": false, "bias": 1, "cap": 320, "mul": true},
]
const L_VIKING := 0
const L_THEMIS := 1
const L_MOLA := 2
const L_CTX := 3
const L_HIRISE := 4

# ---------------- Global places ----------------
const CATS := {
	"Mission sites": {"color": ORANGE, "icon": "mission", "zoom": 6.0},
	"Volcanoes": {"color": HAZ_RED, "icon": "volcano", "zoom": 1.6},
	"Canyons & valleys": {"color": GOLD, "icon": "canyon", "zoom": 0.9},
	"Craters & basins": {"color": BLUE, "icon": "basin", "zoom": 0.8},
	"Plains & regions": {"color": SILVER, "icon": "plain", "zoom": 0.4},
	"Polar regions": {"color": ICE, "icon": "polar", "zoom": 0.7},
}
const FOCUS_ZOOM := {"jezero": 9.0, "perseverance": 20.0}

# id, name, category, lat, lon (east +, -180..180), tier (1 = always shown), description, facts, hide when zoomed into Jezero
const PLACES := [
	["perseverance", "Perseverance", "Mission sites", 18.4447, 77.4508, 1,
		"NASA rover exploring Jezero Crater's ancient river delta and collecting rock samples for a possible return to Earth.",
		[["Agency", "NASA"], ["Landed", "Feb 18, 2021"], ["Status", "Active"]], true],
	["curiosity", "Curiosity", "Mission sites", -4.59, 137.44, 1,
		"NASA rover climbing the layered slopes of Mount Sharp inside Gale Crater to study how Mars lost its habitable climate.",
		[["Agency", "NASA"], ["Landed", "Aug 6, 2012"], ["Status", "Active"]], false],
	["zhurong", "Zhurong", "Mission sites", 25.07, 109.93, 2,
		"China's first Mars rover, part of the Tianwen-1 mission, landed on the southern Utopia Planitia plain.",
		[["Agency", "CNSA"], ["Landed", "May 14, 2021"], ["Status", "Inactive (hibernating since 2022)"]], false],
	["insight", "InSight", "Mission sites", 4.50, 135.62, 2,
		"Stationary lander that measured marsquakes and the planet's interior with a seismometer.",
		[["Agency", "NASA"], ["Landed", "Nov 26, 2018"], ["Status", "Ended (Dec 2022)"]], false],
	["opportunity", "Opportunity", "Mission sites", -1.95, -5.53, 2,
		"Long-lived rover that found clear evidence of past liquid water at Meridiani Planum. It drove about 45 km.",
		[["Agency", "NASA"], ["Landed", "Jan 25, 2004"], ["Status", "Ended (2018)"]], false],
	["spirit", "Spirit", "Mission sites", -14.57, 175.47, 2,
		"Twin of Opportunity. Explored Gusev Crater and the Columbia Hills before getting stuck in soft sand.",
		[["Agency", "NASA"], ["Landed", "Jan 4, 2004"], ["Status", "Ended (2010)"]], false],
	["phoenix", "Phoenix", "Mission sites", 68.22, -125.75, 2,
		"Polar lander that dug into the Arctic soil and confirmed water ice just below the surface.",
		[["Agency", "NASA"], ["Landed", "May 25, 2008"], ["Status", "Ended (Nov 2008)"]], false],
	["pathfinder", "Mars Pathfinder", "Mission sites", 19.13, -33.22, 2,
		"Landed with Sojourner, the first rover ever driven on Mars, in the Ares Vallis flood channel.",
		[["Agency", "NASA"], ["Landed", "Jul 4, 1997"], ["Status", "Ended (Sep 1997)"]], false],
	["viking1", "Viking 1", "Mission sites", 22.27, -47.95, 3,
		"First successful Mars lander. Returned the first color pictures from the surface and tested the soil for life.",
		[["Agency", "NASA"], ["Landed", "Jul 20, 1976"], ["Status", "Ended (1982)"]], false],
	["viking2", "Viking 2", "Mission sites", 47.64, 134.26, 3,
		"Twin of Viking 1 in the northern lowlands of Utopia Planitia. Photographed frost on the ground.",
		[["Agency", "NASA"], ["Landed", "Sep 3, 1976"], ["Status", "Ended (1980)"]], false],
	["beagle2", "Beagle 2", "Mission sites", 11.53, 90.43, 3,
		"British lander that fell silent after arrival. Later images showed it had landed but not fully opened.",
		[["Agency", "ESA / UK"], ["Landed", "Dec 2003"], ["Status", "Lost"]], false],
	["schiaparelli", "Schiaparelli", "Mission sites", -2.05, -6.21, 3,
		"European landing demonstrator that crashed after a descent error, but its orbiter relayed useful data.",
		[["Agency", "ESA"], ["Arrived", "Oct 19, 2016"], ["Status", "Lost"]], false],
	["rosalind", "Rosalind Franklin site", "Mission sites", 18.2, -24.6, 3,
		"Oxia Planum, the chosen landing area for the planned ExoMars rover, which will drill two meters down.",
		[["Agency", "ESA"], ["Status", "Planned (check current schedule)"]], false],

	["olympus", "Olympus Mons", "Volcanoes", 18.65, -133.8, 1,
		"The tallest volcano known in the solar system. A vast shield volcano with gentle slopes and a cliff around its base.",
		[["Type", "Shield volcano"], ["Height", "~22 km"], ["Width", "~600 km"]], false],
	["ascraeus", "Ascraeus Mons", "Volcanoes", 11.8, -104.5, 2,
		"Northernmost and tallest of the three Tharsis Montes volcanoes.",
		[["Type", "Shield volcano"], ["Group", "Tharsis Montes"]], false],
	["pavonis", "Pavonis Mons", "Volcanoes", 0.8, -113.0, 2,
		"The middle Tharsis volcano, sitting almost exactly on the equator.",
		[["Type", "Shield volcano"], ["Group", "Tharsis Montes"]], false],
	["arsia", "Arsia Mons", "Volcanoes", -8.35, -120.1, 2,
		"Southernmost of the Tharsis Montes, with a very wide summit caldera.",
		[["Type", "Shield volcano"], ["Group", "Tharsis Montes"]], false],
	["elysiummons", "Elysium Mons", "Volcanoes", 25.0, 147.2, 2,
		"Main volcano of the Elysium region, far from Tharsis.",
		[["Type", "Shield volcano"]], false],
	["alba", "Alba Mons", "Volcanoes", 40.5, -109.6, 3,
		"A huge, very low volcano with one of the widest footprints on Mars, over 1,000 km across.",
		[["Type", "Shield volcano"]], false],
	["hecates", "Hecates Tholus", "Volcanoes", 32.2, 150.2, 3,
		"Smaller volcano in the Elysium region, cut by channels.",
		[["Type", "Volcanic dome"]], false],
	["apollinaris", "Apollinaris Mons", "Volcanoes", -9.3, 174.4, 3,
		"Isolated volcano at the edge of the southern highlands.",
		[["Type", "Volcano"]], false],

	["vm", "Valles Marineris", "Canyons & valleys", -13.9, -59.2, 1,
		"The largest canyon system in the solar system. It would stretch across the width of the United States.",
		[["Length", "~4,000 km"], ["Depth", "up to ~7 km"]], false],
	["noctis", "Noctis Labyrinthus", "Canyons & valleys", -7.0, -101.0, 3,
		"A maze of deep, criss-crossing valleys at the western end of Valles Marineris.",
		[["Type", "Canyon maze"]], false],
	["kasei", "Kasei Valles", "Canyons & valleys", 24.0, -63.0, 3,
		"One of the largest outflow channels, carved by catastrophic ancient floods.",
		[["Type", "Outflow channel"]], false],
	["candor", "Candor Chasma", "Canyons & valleys", -5.4, -67.3, 3,
		"Central basin of Valles Marineris with bright layered deposits.",
		[["Type", "Chasma"]], false],

	["hellas", "Hellas Planitia", "Craters & basins", -42.7, 70.0, 1,
		"The deepest and broadest visible impact basin on Mars. Dust storms often start in and around it.",
		[["Diameter", "~2,300 km"], ["Depth", "~7 km"]], false],
	["argyre", "Argyre Planitia", "Craters & basins", -49.7, -44.0, 2,
		"Large, bright impact basin in the southern highlands, often covered in frost in winter.",
		[["Diameter", "~1,800 km"]], false],
	["isidis", "Isidis Planitia", "Craters & basins", 12.9, 87.0, 2,
		"Large basin on the dichotomy boundary. Jezero Crater lies on its western edge.",
		[["Diameter", "~1,500 km"]], false],
	["utopia", "Utopia Planitia", "Craters & basins", 46.7, 117.5, 2,
		"Vast northern plain and one of the largest impact basins in the solar system.",
		[["Diameter", "~3,300 km (estimated)"]], false],
	["jezero", "Jezero Crater", "Craters & basins", 18.38, 77.58, 1,
		"Ancient lake basin with a well-preserved river delta. The focus site of this atlas and home of Perseverance.",
		[["Diameter", "~45 km"], ["Feature", "River delta"]], true],
	["gale", "Gale Crater", "Craters & basins", -5.4, 137.8, 2,
		"Crater with a 5 km tall central mound, Mount Sharp, built from layered sediment.",
		[["Diameter", "~154 km"]], false],
	["gusev", "Gusev Crater", "Craters & basins", -14.5, 175.4, 3,
		"Crater that may once have held a lake, explored by Spirit.",
		[["Diameter", "~166 km"]], false],
	["endeavour", "Endeavour Crater", "Craters & basins", -2.3, -5.2, 3,
		"Crater whose rim Opportunity explored for years, finding clay minerals.",
		[["Diameter", "~22 km"]], false],
	["korolev", "Korolev Crater", "Craters & basins", 73.0, 165.0, 3,
		"Well-preserved crater holding a permanent mound of water ice.",
		[["Diameter", "~82 km"]], false],
	["galle", "Galle Crater", "Craters & basins", -51.0, -30.9, 3,
		"Known as the 'Happy Face' crater because of its smiley shape in orbital images.",
		[["Type", "Impact crater"]], false],

	["tharsis", "Tharsis Bulge", "Plains & regions", 1.0, -110.0, 1,
		"Enormous volcanic plateau holding the biggest volcanoes on Mars.",
		[["Type", "Volcanic plateau"]], false],
	["chryse", "Chryse Planitia", "Plains & regions", 28.4, -40.8, 2,
		"Low plain where ancient floods drained. Viking 1 and Pathfinder landed nearby.",
		[["Type", "Plain"]], false],
	["syrtis", "Syrtis Major", "Plains & regions", 8.4, 69.5, 3,
		"Dark volcanic plateau, visible even from telescopes on Earth.",
		[["Type", "Volcanic plateau"]], false],
	["meridiani", "Meridiani Planum", "Plains & regions", 0.0, -5.0, 3,
		"Flat plain rich in hematite, where Opportunity found evidence of past water.",
		[["Type", "Plain"]], false],
	["elysiumpl", "Elysium Planitia", "Plains & regions", 3.0, 154.7, 3,
		"Smooth equatorial plain, home of the InSight lander.",
		[["Type", "Plain"]], false],
	["amazonis", "Amazonis Planitia", "Plains & regions", 24.8, -164.8, 3,
		"Very smooth, young lowland plain.",
		[["Type", "Plain"]], false],
	["acidalia", "Acidalia Planitia", "Plains & regions", 46.7, -22.0, 3,
		"Large northern plain, a common starting area for regional dust storms.",
		[["Type", "Plain"]], false],

	["npc", "North Polar Cap", "Polar regions", 85.0, 0.0, 1,
		"Layered ice cap made mostly of water ice, covered by seasonal carbon dioxide frost.",
		[["Name", "Planum Boreum"]], false],
	["spc", "South Polar Cap", "Polar regions", -87.0, 0.0, 1,
		"Cap with a permanent layer of carbon dioxide ice over water ice.",
		[["Name", "Planum Australe"]], false],
]

# ---------------- Jezero operations (local detail) ----------------
const COND := {
	"Clear": {"color": GREEN, "drive": "GO", "wind": 8},
	"Cold": {"color": BLUE, "drive": "GO", "wind": 10},
	"Dusty": {"color": GOLD, "drive": "CAUTION", "wind": 25},
	"Dust devils": {"color": GOLD, "drive": "CAUTION", "wind": 40},
	"Strong wind": {"color": VIOLET, "drive": "CAUTION", "wind": 70},
	"Dust storm": {"color": HAZ_RED, "drive": "NO-GO", "wind": 90},
}
const RANK := {"GO": 0, "CAUTION": 1, "NO-GO": 2}

const GROUPS := {
	"Safe zones": {"color": GREEN, "status": "SAFE", "min_drive": "GO"},
	"Slope hazards": {"color": ORANGE, "status": "HAZARD", "min_drive": "CAUTION"},
	"Boulder & dune hazards": {"color": HAZ_RED, "status": "HAZARD", "min_drive": "CAUTION"},
	"Science targets": {"color": BLUE, "status": "SCIENCE", "min_drive": "GO"},
	"Dust zones": {"color": GOLD, "status": "DUSTY", "min_drive": "CAUTION"},
	"Wind zones": {"color": VIOLET, "status": "STRONG WIND", "min_drive": "CAUTION"},
	"Landmarks": {"color": SILVER, "status": "LANDMARK", "min_drive": "GO"},
}

const SITES := [
	["Safe zones", "Landing site", 18.4447, 77.4508, 2.0,
		"Perseverance touched down here on Feb 18, 2021. Flat, low-risk ground.", "Clear"],
	["Safe zones", "Ingenuity airfield", 18.46, 77.47, 1.0,
		"Smooth, flat patch used as the helicopter airfield. Placement approximate.", "Clear"],
	["Safe zones", "Eastern crater floor", 18.30, 77.68, 3.0,
		"Broad, low-relief floor. Illustrative low-slope zone.", "Clear"],
	["Safe zones", "Northern floor plain", 18.50, 77.60, 3.0,
		"Smooth plains with few rocks. Illustrative safe zone.", "Cold"],
	["Safe zones", "Sheltered ridge lee", 18.50, 77.52, 1.5,
		"Ridge blocks the wind here, so it is a calm place to wait out a storm.", "Clear"],

	["Slope hazards", "Delta scarp", 18.49, 77.37, 1.5,
		"Steep delta front. Hard to drive or land on.", "Clear"],
	["Slope hazards", "Western crater rim", 18.38, 77.30, 3.5,
		"Steep, rough rim terrain, exposed to wind.", "Strong wind"],
	["Slope hazards", "Southern crater rim", 18.17, 77.58, 3.5,
		"Steep rim wall with loose rock.", "Strong wind"],
	["Slope hazards", "Northern crater rim", 18.60, 77.52, 3.5,
		"Steep rim wall, broken by gullies.", "Cold"],

	["Boulder & dune hazards", "Rock field", 18.415, 77.435, 1.2,
		"Boulders that can block or damage a rover.", "Clear"],
	["Boulder & dune hazards", "Megaripple field", 18.36, 77.46, 2.5,
		"Wind-blown ripples where wheels can slip or sink.", "Dusty"],
	["Boulder & dune hazards", "Eastern dune field", 18.25, 77.82, 3.0,
		"Active dunes. Soft sand can trap wheels.", "Strong wind"],
	["Boulder & dune hazards", "Debris field", 18.432, 77.437, 0.6,
		"Scattered hardware and rocks near where the descent stage came down. Approximate.", "Clear"],

	["Science targets", "River delta", 18.43, 77.37, 2.5,
		"Ancient river delta. A prime place to search for signs of past microbial life.", "Clear"],
	["Science targets", "Seitah region", 18.40, 77.40, 2.0,
		"Ridged, olivine-rich rocks that record early volcanic history.", "Clear"],
	["Science targets", "Sample depot", 18.47, 77.40, 1.0,
		"Area where sample tubes were cached for a possible future return mission. Location approximate.", "Clear"],
	["Science targets", "Neretva Vallis", 18.47, 77.27, 2.0,
		"Ancient inlet channel where a river once entered the crater.", "Cold"],
	["Science targets", "Margin unit", 18.22, 77.78, 3.0,
		"Band of rock along the inner rim, rich in carbonates. A key target for habitability.", "Clear"],
	["Science targets", "Crater floor rocks", 18.35, 77.55, 2.5,
		"Dark volcanic floor rocks. Dating them helps set the age of the crater.", "Clear"],
	["Science targets", "Layered delta top", 18.46, 77.34, 1.5,
		"Stacked layers that record how the lake level changed over time.", "Strong wind"],

	["Dust zones", "Dust storm corridor", 18.62, 77.65, 5.0,
		"Seasonal dust storms can sweep through here. Visibility and solar power drop.", "Dust storm"],
	["Dust zones", "Dust devil alley", 18.32, 77.52, 3.0,
		"Dust devils are common on the crater floor. Short bursts of wind and dust.", "Dust devils"],
	["Dust zones", "Fine dust basin", 18.28, 77.40, 3.0,
		"Loose, fine dust. Lower traction and dusty solar panels.", "Dusty"],
	["Dust zones", "Dusty southern plain", 18.20, 77.66, 3.0,
		"Thin dust layer that lifts easily and hazes the sky.", "Dusty"],

	["Wind zones", "Rim wind belt", 18.55, 77.30, 3.0,
		"Wind funnels over the rim. Gusts can kick up dust and stress equipment.", "Strong wind"],
	["Wind zones", "Delta wind gap", 18.52, 77.43, 2.0,
		"Gap between ridges that channels strong wind.", "Strong wind"],
	["Wind zones", "Eastern slope winds", 18.42, 77.90, 3.0,
		"Downslope winds along the eastern rim.", "Strong wind"],
	["Wind zones", "Southern gust corridor", 18.22, 77.46, 2.5,
		"Gusty corridor between the rim and the dunes.", "Strong wind"],

	["Landmarks", "Crater center", 18.38, 77.58, 1.2,
		"Geometric center of the roughly 45 km wide Jezero crater.", "Clear"],
	["Landmarks", "Heat shield impact", 18.452, 77.493, 0.5,
		"Where the heat shield landed after it separated during entry. Approximate.", "Clear"],
	["Landmarks", "Backshell & parachute", 18.438, 77.468, 0.5,
		"Where the parachute and backshell came to rest. Approximate.", "Clear"],
]

const ROUTES := [
	{"name": "Safe route", "color": GREEN, "dashed": false,
		"wp": [[18.4447, 77.4508, "Landing site"], [18.448, 77.43, "Smooth plain"], [18.44, 77.40, "Delta approach"], [18.432, 77.378, "Delta base"]],
		"info": "Recommended path from the landing site to the delta. Stays clear of the rock field and the steep scarp.",
		"status": "RECOMMENDED ROUTE", "diff": "Easy", "slope": 6.0, "note": "Stable solar power along the whole path."},
	{"name": "Direct route", "color": HAZ_RED, "dashed": true,
		"wp": [[18.4447, 77.4508, "Landing site"], [18.415, 77.435, "Rock field edge"], [18.425, 77.40, "Boulder channel"], [18.432, 77.378, "Delta base"]],
		"info": "Shorter, but it crosses the rock field. Avoid.",
		"status": "AVOID", "diff": "Hard", "slope": 18.0, "note": "High risk of wheel damage and getting stuck."},
	{"name": "Science traverse", "color": BLUE, "dashed": false,
		"wp": [[18.432, 77.378, "Delta base"], [18.415, 77.392, "Ridge outcrop"], [18.40, 77.40, "Seitah edge"]],
		"info": "From the delta to the Seitah ridges for rock sampling.",
		"status": "SCIENCE ROUTE", "diff": "Moderate", "slope": 12.0, "note": "Slow driving. Many stops for rock sampling."},
	{"name": "Rim climb", "color": GOLD, "dashed": false,
		"wp": [[18.432, 77.378, "Delta base"], [18.47, 77.36, "Delta top"], [18.50, 77.31, "Upper channel"], [18.55, 77.30, "Rim wind belt"]],
		"info": "Climb from the delta to the rim. Exposed to strong wind near the top.",
		"status": "CAUTION ROUTE", "diff": "Hard", "slope": 20.0, "note": "Wind gusts near the top. Check the forecast first."},
	{"name": "Airfield shuttle", "color": GREEN, "dashed": false,
		"wp": [[18.4447, 77.4508, "Landing site"], [18.452, 77.462, "Flat patch"], [18.46, 77.47, "Ingenuity airfield"]],
		"info": "Short, smooth hop from the landing site to the helicopter airfield.",
		"status": "RECOMMENDED ROUTE", "diff": "Easy", "slope": 3.0, "note": "Very flat. Ideal for quick trips."},
	{"name": "Sample depot run", "color": GREEN, "dashed": false,
		"wp": [[18.4447, 77.4508, "Landing site"], [18.452, 77.43, "Smooth plain"], [18.462, 77.415, "Gravel bench"], [18.47, 77.40, "Sample depot"]],
		"info": "Carries sample tubes from the landing area to the depot.",
		"status": "RECOMMENDED ROUTE", "diff": "Easy", "slope": 8.0, "note": "Gravel bench slows the wheels slightly."},
	{"name": "Eastern floor survey", "color": GOLD, "dashed": false,
		"wp": [[18.4447, 77.4508, "Landing site"], [18.40, 77.52, "Dust devil alley"], [18.32, 77.60, "Open floor"], [18.30, 77.68, "Eastern floor"], [18.24, 77.76, "Dune margin"], [18.22, 77.78, "Margin unit"]],
		"info": "Long survey across the crater floor to the carbonate-rich margin unit.",
		"status": "CAUTION ROUTE", "diff": "Moderate", "slope": 10.0, "note": "Crosses dust devil alley. Watch for sudden dust."},
	{"name": "Storm shelter run", "color": ORANGE, "dashed": false,
		"wp": [[18.62, 77.65, "Storm corridor"], [18.55, 77.58, "Northern plain"], [18.50, 77.52, "Sheltered ridge lee"], [18.4447, 77.4508, "Landing site"]],
		"info": "Emergency retreat from the dust storm corridor to calmer ground.",
		"status": "EMERGENCY ROUTE", "diff": "Moderate", "slope": 9.0, "note": "Use when a storm approaches. Panels may charge slowly."},
	{"name": "Neretva traverse", "color": BLUE, "dashed": false,
		"wp": [[18.432, 77.378, "Delta base"], [18.45, 77.33, "Delta west flank"], [18.47, 77.27, "Neretva Vallis"]],
		"info": "Follows the ancient river channel upstream.",
		"status": "SCIENCE ROUTE", "diff": "Moderate", "slope": 14.0, "note": "Cold shadows. Slower battery charging."},
]

const TRAVEL_MODES := [["Science rover", 0.14], ["Crewed rover (concept)", 15.0], ["Rotorcraft (concept)", 36.0]]

# ---------------- Map objects ----------------
class Zone extends Node2D:
	var radius := 10.0
	var full_radius := 10.0
	var home := Vector2.ZERO
	var pinned := false
	var color := Color.WHITE
	var title := ""
	var group := ""
	var info := ""
	var cond := "Clear"
	var lat := 0.0
	var lon := 0.0
	var px := 0.1
	var hover := false
	var selected := false
	var anim := 0.0
	var label := Label.new()
	func _ready() -> void:
		label.text = title
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		add_child(label)
		set_process(false)
		set_px(px)
	func _refresh_label() -> void:
		label.visible = px < 0.14 or hover or selected
	func set_px(p: float) -> void:
		px = p
		label.position = Vector2(radius + 4.0 * px, -8.0 * px)
		label.scale = Vector2(px, px)
		_refresh_label()
		queue_redraw()
	func set_hover(v: bool) -> void:
		if hover != v:
			hover = v
			_refresh_label()
			queue_redraw()
	func set_selected(v: bool) -> void:
		selected = v
		set_process(v)
		_refresh_label()
		queue_redraw()
	func _process(delta: float) -> void:
		anim += delta
		queue_redraw()
	func _draw() -> void:
		var fill := 0.22
		var wd := 2.0
		if hover or selected:
			fill = 0.38
			wd = 3.0
		draw_circle(Vector2.ZERO, radius, Color(color, fill))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, color, wd * px)
		draw_circle(Vector2.ZERO, 3.0 * px, color)
		if selected:
			var k := fposmod(anim, 1.4) / 1.4
			draw_arc(Vector2.ZERO, radius * (1.0 + 0.5 * k), 0.0, TAU, 64, Color(color, 1.0 - k), 2.0 * px)

class Route extends Node2D:
	var pts := PackedVector2Array()
	var names: Array = []
	var color := Color.WHITE
	var dashed := false
	var px := 0.1
	var progress := -1.0
	var reveal := 1.0:
		set(v):
			reveal = v
			queue_redraw()
	var hover := false
	var selected := false
	var anim := 0.0
	var title := ""
	var info := ""
	var status := ""
	var diff := ""
	var slope := 0.0
	var note := ""
	var length_km := 0.0
	var label := Label.new()
	var wp_labels: Array = []
	func _style(l: Label, size: int) -> void:
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
	func _ready() -> void:
		label.text = title
		_style(label, 12)
		add_child(label)
		for nm in names:
			var l := Label.new()
			l.text = str(nm)
			_style(l, 11)
			l.visible = false
			add_child(l)
			wp_labels.append(l)
		set_process(false)
		set_px(px)
	func set_px(p: float) -> void:
		px = p
		var mid: Vector2 = pts[pts.size() >> 1]
		label.position = mid + Vector2(8.0 * px, -22.0 * px)
		label.scale = Vector2(px, px)
		for i in range(wp_labels.size()):
			var l: Label = wp_labels[i]
			l.position = pts[i] + Vector2(9.0 * px, 6.0 * px)
			l.scale = Vector2(px, px)
		queue_redraw()
	func set_hover(v: bool) -> void:
		if hover != v:
			hover = v
			queue_redraw()
	func set_selected(v: bool) -> void:
		selected = v
		set_process(v)
		for l in wp_labels:
			l.visible = v
		queue_redraw()
	func _process(delta: float) -> void:
		anim += delta
		queue_redraw()
	func total_len() -> float:
		var total := 0.0
		for i in range(pts.size() - 1):
			total += pts[i].distance_to(pts[i + 1])
		return total
	func _at_dist(d: float) -> Dictionary:
		var rem := d
		for i in range(pts.size() - 1):
			var seg := pts[i].distance_to(pts[i + 1])
			if rem <= seg or i == pts.size() - 2:
				var f := 0.0
				if seg > 0.0:
					f = clampf(rem / seg, 0.0, 1.0)
				return {"p": pts[i].lerp(pts[i + 1], f), "d": (pts[i + 1] - pts[i]).normalized()}
			rem -= seg
		return {"p": pts[0], "d": Vector2.RIGHT}
	func point_at(u: float) -> Vector2:
		var r := _at_dist(total_len() * clampf(u, 0.0, 1.0))
		return r["p"]
	func dir_at(u: float) -> Vector2:
		var r := _at_dist(total_len() * clampf(u, 0.0, 1.0))
		return r["d"]
	func dist_to(p: Vector2) -> float:
		var best := INF
		for i in range(pts.size() - 1):
			var c := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			best = minf(best, c.distance_to(p))
		return best
	func vis_pts() -> PackedVector2Array:
		if reveal >= 0.999:
			return pts
		var out := PackedVector2Array([pts[0]])
		var target := total_len() * reveal
		for i in range(pts.size() - 1):
			var seg := pts[i].distance_to(pts[i + 1])
			if target >= seg:
				out.append(pts[i + 1])
				target -= seg
			else:
				if seg > 0.0:
					out.append(pts[i].lerp(pts[i + 1], target / seg))
				break
		return out
	func _tri(m: Vector2, d: Vector2, s: float) -> void:
		var nrm := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([
			m + d * s, m - d * s * 0.7 + nrm * s * 0.7, m - d * s * 0.7 - nrm * s * 0.7]), Color.WHITE)
	func _draw() -> void:
		if reveal <= 0.001 or pts.size() < 2:
			return
		var dark := Color(0, 0, 0, 0.85)
		var w := 4.0 * px
		if hover or selected:
			w = 6.0 * px
		var vp := vis_pts()
		if dashed:
			for i in range(vp.size() - 1):
				if vp[i].distance_to(vp[i + 1]) > 0.000001:
					draw_dashed_line(vp[i], vp[i + 1], dark, w + 3.0 * px, 10.0 * px)
					draw_dashed_line(vp[i], vp[i + 1], color, w, 10.0 * px)
		elif vp.size() >= 2:
			draw_polyline(vp, dark, w + 3.0 * px, true)
			draw_polyline(vp, color, w, true)
		var total := total_len()
		if selected:
			var sp := 34.0 * px
			var n := mini(int(total / sp) + 1, 200)
			var off := fposmod(anim * 22.0 * px, sp)
			for i in range(n):
				var dd := off + i * sp
				if dd > total * reveal:
					break
				var a := _at_dist(dd)
				_tri(a["p"], a["d"], 7.0 * px)
		else:
			for i in range(vp.size() - 1):
				var seg := vp[i].distance_to(vp[i + 1])
				if seg > 0.000001:
					_tri((vp[i] + vp[i + 1]) * 0.5, (vp[i + 1] - vp[i]).normalized(), 8.0 * px)
		var cum := 0.0
		for i in range(pts.size()):
			if i > 0:
				cum += pts[i - 1].distance_to(pts[i])
			if cum > total * reveal + 0.0001:
				break
			var r := 4.0 * px
			var fill := color
			if i == 0:
				r = 6.0 * px
				fill = Color.WHITE
			elif i == pts.size() - 1:
				r = 6.0 * px
			draw_circle(pts[i], r + 1.5 * px, dark)
			draw_circle(pts[i], r, fill)
		if progress >= 0.0:
			var p := point_at(progress)
			var glow := 0.5 + 0.5 * sin(anim * 6.0)
			draw_circle(p, (11.0 + 3.0 * glow) * px, Color(color, 0.35))
			draw_circle(p, 9.0 * px, dark)
			draw_circle(p, 7.0 * px, Color.WHITE)
			draw_circle(p, 4.0 * px, color)

# Lat/lon grid in world space
class Graticule extends Node2D:
	var px := 0.1
	var ox := 0.0
	var oy := 0.0
	var ww := 65536.0
	var wh := 32768.0
	func set_px(p: float) -> void:
		px = p
		queue_redraw()
	func _draw() -> void:
		for i in range(13):
			var x := float(i) / 12.0 * ww - ox
			var a := 0.12
			if i == 6:
				a = 0.4
			draw_line(Vector2(x, -oy), Vector2(x, wh - oy), Color(1, 1, 1, a), px)
		for j in range(7):
			var y := float(j) / 6.0 * wh - oy
			var a2 := 0.12
			if j == 3:
				a2 = 0.4
			draw_line(Vector2(-ox, y), Vector2(ww - ox, y), Color(1, 1, 1, a2), px)

# Screen-space overlay (pins, labels, navigation route). Drawing is done by the main script.
class PoiView extends Control:
	var app: Node2D
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func _draw() -> void:
		if app != null:
			app.draw_overlay(self)

class MiniMap extends Control:
	signal picked(pos: Vector2)
	var app: Node2D
	func _draw() -> void:
		if app != null:
			app.draw_minimap(self)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(e.position)
		elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			picked.emit(e.position)

# ---------------- State ----------------
var world_w := 65536.0
var world_h := 32768.0
var ox := 0.0
var oy := 0.0
var px_per_km := 3.0
var vp_size := Vector2(1920, 1080)
var min_zoom := 0.03
var cam := Camera2D.new()
var zoom_target := 0.05
var pos_target := Vector2.ZERO
var anchor_active := false
var anchor_world := Vector2.ZERO
var anchor_off := Vector2.ZERO
var follow_rover := false
var dragging := false
var press_pos := Vector2.ZERO
var last_zoom := -1.0
var last_sig := ""
var view_timer := 0.0
var clock_timer := 0.0
var mm_timer := 0.0
var label_timer := 0.0
var anim_t := 0.0
var cur_z := 7
var last_cur_z := -99

# imagery
var sharp_mat: ShaderMaterial
var sharp_layer: CanvasLayer
var sharp_idx := 2
var layers: Array = []
var queue: Array = []
var tiles := {}
var inflight := {}
var failed := {}
var ready_tiles: Array = []
var decoding := 0
var active := 0
var ok_total := 0
var basemap := 0
var ctx_on := true
var hirise_on := false
var tint_on := false
var detail_strength := 1.0
var graticule: Graticule
var mini_tex: Array = [null, null]

# places
var places: Array = []
var draw_order: Array = []
var prio_order: Array = []
var cat_on := {}
var query := ""
var sel_place := -1
var hover_place := -1
var label_ok := {}

# Jezero operations
var local_root: Node2D
var local_alpha := 0.0
var overlay_nodes := {}
var zones: Array[Zone] = []
var routes: Array[Route] = []
var sel_local = null
var hover_local = null
var selected_route: Route = null
var playing := false
var detail_tween: Tween

# navigation
var nav_segs: Array = []
var nav_a := -1
var nav_b := -1

# UI refs
var poi: PoiView
var mm: MiniMap
var tab_btns: Array = []
var tab_scrolls: Array = []
var tab_bodies: Array = []
var list_box: VBoxContainer
var list_count: Label
var search_edit: LineEdit
var from_opt: OptionButton
var to_opt: OptionButton
var nav_info: Label
var layer_stats: Label
var sharp_btn: Button
var tile_status: Label
var res_label: Label
var coord_label: Label
var clock_label: Label
var scale_line: ColorRect
var scale_lbl: Label
var card_panel: PanelContainer
var card_dot: ColorRect
var card_chip: Label
var card_title: Label
var card_sub: Label
var card_body: Label
var card_rows: VBoxContainer
var card_tele: Label
var play_btn: Button
var btn_zoom: Button
var btn_from: Button
var btn_to: Button

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.02, 0.0, 0.01))
	if USE_CACHE:
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	world_w = float(TILE) * pow(2.0, WORLD_Z + 1)
	world_h = float(TILE) * pow(2.0, WORLD_Z)
	ox = _abs_x(CENTER.y)
	oy = _abs_y(CENTER.x)
	px_per_km = TILE * pow(2.0, WORLD_Z + 1) / 360.0 / KM_PER_DEG
	vp_size = get_viewport_rect().size
	zoom_target = 0.05
	cam.zoom = Vector2(0.05, 0.05)
	cam.position = Vector2(world_w * 0.5 - ox, world_h * 0.5 - oy)
	pos_target = cam.position
	add_child(cam)

	# one full-screen sharpen pass (layer 1, above the map, below pins and UI)
	var shader := Shader.new()
	shader.code = SHARPEN_SHADER
	sharp_mat = ShaderMaterial.new()
	sharp_mat.shader = shader
	sharp_layer = CanvasLayer.new()
	sharp_layer.layer = 1
	add_child(sharp_layer)
	var srect := ColorRect.new()
	srect.set_anchors_preset(Control.PRESET_FULL_RECT)
	srect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srect.material = sharp_mat
	sharp_layer.add_child(srect)
	_apply_sharpen()

	var mul_mat := CanvasItemMaterial.new()
	mul_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	for def in LAYER_DEFS:
		var node := Node2D.new()
		node.z_index = int(def["order"])
		if bool(def["mul"]):
			node.material = mul_mat
		add_child(node)
		layers.append({"def": def, "node": node, "min": int(def["min"]), "max": int(def["max"]),
			"ext": 0, "confirmed": false, "ok": {}, "bad": {}})

	graticule = Graticule.new()
	graticule.ox = ox
	graticule.oy = oy
	graticule.ww = world_w
	graticule.wh = world_h
	graticule.z_index = 900
	add_child(graticule)

	# ---- Jezero operations ----
	local_root = Node2D.new()
	local_root.z_index = 1000
	add_child(local_root)
	for s in SITES:
		var g: String = s[0]
		if not overlay_nodes.has(g):
			var holder := Node2D.new()
			local_root.add_child(holder)
			overlay_nodes[g] = holder
		var z := Zone.new()
		var slat: float = s[2]
		var slon: float = s[3]
		var skm: float = s[4]
		z.group = g
		z.title = s[1]
		z.lat = slat
		z.lon = slon
		z.position = _ll(slat, slon)
		z.radius = skm * px_per_km
		z.full_radius = z.radius
		z.home = z.position
		z.pinned = (z.title == "Landing site")
		z.info = s[5]
		z.cond = s[6]
		z.color = GROUPS[g]["color"]
		z.px = 1.0 / cam.zoom.x
		overlay_nodes[g].add_child(z)
		zones.append(z)
	_declutter_zones()

	for r in ROUTES:
		var rt := Route.new()
		var wp: Array = r["wp"]
		var km := 0.0
		for i in range(wp.size()):
			var cur: Array = wp[i]
			var clat: float = cur[0]
			var clon: float = cur[1]
			rt.pts.append(_ll(clat, clon))
			rt.names.append(cur[2])
			if i < wp.size() - 1:
				var nxt: Array = wp[i + 1]
				var nlat: float = nxt[0]
				var nlon: float = nxt[1]
				var dlat := (nlat - clat) * KM_PER_DEG
				var dlon := (nlon - clon) * KM_PER_DEG * cos(deg_to_rad(clat))
				km += sqrt(dlat * dlat + dlon * dlon)
		rt.length_km = km
		rt.title = r["name"]
		rt.color = r["color"]
		rt.dashed = r["dashed"]
		rt.info = r["info"]
		rt.status = r["status"]
		rt.diff = r["diff"]
		rt.slope = float(r["slope"])
		rt.note = r["note"]
		rt.px = 1.0 / cam.zoom.x
		rt.z_index = 100
		local_root.add_child(rt)
		routes.append(rt)
	local_root.visible = false

	# ---- global places ----
	for cat in CATS:
		cat_on[cat] = true
	for e in PLACES:
		var cat: String = e[2]
		var cd: Dictionary = CATS[cat]
		var facts: Array = e[7]
		var ring := Color.WHITE
		for f in facts:
			if f[0] == "Status":
				var st := str(f[1])
				if st.begins_with("Active"):
					ring = GREEN
				elif st.begins_with("Planned"):
					ring = GOLD
				elif st.begins_with("Lost"):
					ring = HAZ_RED
				else:
					ring = Color(0.62, 0.62, 0.68)
		places.append({"id": e[0], "name": e[1], "cat": cat, "lat": float(e[3]), "lon": float(e[4]),
			"tier": int(e[5]), "info": e[6], "facts": facts, "hide_local": bool(e[8]),
			"color": cd["color"], "icon": cd["icon"], "ring": ring, "pos": _ll(float(e[3]), float(e[4]))})
	prio_order = range(places.size())
	prio_order.sort_custom(func(a, b): return int(places[a]["tier"]) < int(places[b]["tier"]))
	draw_order = prio_order.duplicate()
	draw_order.reverse()

	_build_ui()
	_apply_layers()
	_refresh_list()
	_update_clock()
	_load_mini()
	get_tree().create_timer(1.2).timeout.connect(_intro)

func _intro() -> void:
	_fly_to(_ll(CRATER_CENTER.x, CRATER_CENTER.y), 2.5)

func _abs_x(lon: float) -> float:
	return (lon + 180.0) / 360.0 * TILE * pow(2.0, WORLD_Z) * 2.0

func _abs_y(lat: float) -> float:
	return (90.0 - lat) / 180.0 * TILE * pow(2.0, WORLD_Z)

func _ll(lat: float, lon: float) -> Vector2:
	return Vector2(_abs_x(lon) - ox, _abs_y(lat) - oy)

func _s(p: Vector2) -> Vector2:
	return (p - cam.position) * cam.zoom.x + vp_size * 0.5

func _declutter_zones() -> void:
	var gap := ZONE_GAP_KM * px_per_km
	var min_r := ZONE_MIN_KM * px_per_km
	for z in zones:
		z.radius = maxf(z.full_radius * ZONE_SCALE, min_r)
	for _iter in range(80):
		var moved := false
		for a in range(zones.size()):
			for b in range(a + 1, zones.size()):
				var za: Zone = zones[a]
				var zb: Zone = zones[b]
				var diff := zb.position - za.position
				var d := diff.length()
				if d >= za.radius + zb.radius + gap:
					continue
				moved = true
				var f := maxf(d - gap, 0.0) / (za.radius + zb.radius)
				za.radius = maxf(za.radius * f, min_r)
				zb.radius = maxf(zb.radius * f, min_r)
				var overlap := za.radius + zb.radius + gap - d
				if overlap <= 0.0:
					continue
				var dir := Vector2.RIGHT.rotated(float(a) * 0.9 + float(b))
				if d > 0.001:
					dir = diff / d
				if za.pinned and zb.pinned:
					continue
				elif za.pinned:
					zb.position += dir * overlap
				elif zb.pinned:
					za.position -= dir * overlap
				else:
					za.position -= dir * overlap * 0.5
					zb.position += dir * overlap * 0.5
		if not moved:
			break
	for z in zones:
		z.set_px(1.0 / cam.zoom.x)

func _apply_sharpen() -> void:
	var v := float(SHARP_VALUES[sharp_idx])
	sharp_mat.set_shader_parameter("strength", v)
	if sharp_layer != null:
		sharp_layer.visible = v > 0.0

func _cycle_sharp() -> void:
	sharp_idx = (sharp_idx + 1) % SHARP_NAMES.size()
	_apply_sharpen()
	sharp_btn.text = "Sharpen: " + str(SHARP_NAMES[sharp_idx])

# ---------------- Layers ----------------
func _set_layer(li: int, vis: bool, a: float) -> void:
	var st: Dictionary = layers[li]
	var def: Dictionary = st["def"]
	var node: Node2D = st["node"]
	var g := 1.0
	if bool(def["mul"]):
		g = DETAIL_GAIN
	node.modulate = Color(g, g, g, a)
	node.visible = vis
	last_sig = ""

func _apply_layers() -> void:
	_set_layer(L_VIKING, basemap == 0, 1.0)
	_set_layer(L_THEMIS, basemap == 2, 1.0)
	var mola_vis := basemap == 1 or (basemap == 0 and tint_on)
	var mola_a := 0.5
	if basemap == 1:
		mola_a = 1.0
	_set_layer(L_MOLA, mola_vis, mola_a)
	var ca := detail_strength
	if basemap == 1:
		ca = detail_strength * 0.45
	_set_layer(L_CTX, ctx_on and basemap != 2, ca)
	_set_layer(L_HIRISE, hirise_on and basemap != 2, detail_strength)

func _set_basemap(i: int) -> void:
	basemap = i
	_apply_layers()

func _on_ctx(on: bool) -> void:
	ctx_on = on
	_apply_layers()

func _on_hirise(on: bool) -> void:
	hirise_on = on
	_apply_layers()

func _on_tint(on: bool) -> void:
	tint_on = on
	_apply_layers()

func _on_strength(v: float) -> void:
	detail_strength = v
	_apply_layers()

func _on_grid(on: bool) -> void:
	graticule.visible = on

# ---------------- Frame loop ----------------
func _clamp_center(p: Vector2, z: float) -> Vector2:
	var half := vp_size / (2.0 * z)
	var out := p
	var xmin := -ox
	var xmax := world_w - ox
	var ymin := -oy
	var ymax := world_h - oy
	if xmax - xmin <= half.x * 2.0:
		out.x = (xmin + xmax) * 0.5
	else:
		out.x = clampf(p.x, xmin + half.x, xmax - half.x)
	if ymax - ymin <= half.y * 2.0:
		out.y = (ymin + ymax) * 0.5
	else:
		out.y = clampf(p.y, ymin + half.y, ymax - half.y)
	return out

func _process(delta: float) -> void:
	anim_t += delta
	vp_size = get_viewport_rect().size
	min_zoom = maxf(vp_size.x / world_w, vp_size.y / world_h)

	var nadd := mini(ready_tiles.size(), MAX_ADD_PER_FRAME)
	for i in range(nadd):
		_add_tile(ready_tiles.pop_front())

	var k := 1.0 - exp(-9.0 * delta)
	zoom_target = clampf(zoom_target, min_zoom, MAX_ZOOM)
	var zc := exp(lerpf(log(cam.zoom.x), log(zoom_target), k))
	zc = clampf(zc, min_zoom, MAX_ZOOM)
	cam.zoom = Vector2(zc, zc)
	if playing and follow_rover and selected_route != null:
		pos_target = selected_route.point_at(selected_route.progress)
	if anchor_active:
		cam.position = anchor_world - anchor_off / zc
		pos_target = cam.position
		if absf(log(zc) - log(zoom_target)) < 0.002:
			anchor_active = false
	else:
		cam.position = cam.position.lerp(pos_target, k)
	cam.position = _clamp_center(cam.position, zc)
	pos_target = _clamp_center(pos_target, zc)

	local_alpha = clampf((zc - LOCAL_FADE) / (LOCAL_ZOOM - LOCAL_FADE), 0.0, 1.0)
	local_root.visible = local_alpha > 0.01
	local_root.modulate.a = local_alpha

	if last_zoom < 0.0 or absf(zc / last_zoom - 1.0) > 0.004:
		last_zoom = zc
		graticule.set_px(1.0 / zc)
		if local_root.visible:
			for zn in zones:
				zn.set_px(1.0 / zc)
			for rt in routes:
				rt.set_px(1.0 / zc)
		_update_scale()

	if playing and selected_route != null:
		var rt2 := selected_route
		rt2.progress += delta * 0.6 / maxf(rt2.length_km, 0.1)
		if rt2.progress >= 1.0:
			rt2.progress = 1.0
			playing = false
			follow_rover = false
			play_btn.text = "Replay rover"
		var u := rt2.progress
		var dir := rt2.dir_at(u)
		var heading := fposmod(rad_to_deg(atan2(dir.x, -dir.y)), 360.0)
		var sl := rt2.slope * (0.4 + 0.6 * absf(sin(u * TAU * 1.5)))
		card_tele.text = "Rover: %.1f / %.1f km   Heading %03d°   Slope ~%d°" % [u * rt2.length_km, rt2.length_km, int(heading), int(sl)]
		card_tele.visible = true
		rt2.queue_redraw()

	view_timer += delta
	if view_timer >= 0.2:
		view_timer = 0.0
		var sig := "%.4f|%.4f|%.3f|%d" % [cam.position.x, cam.position.y, cam.zoom.x, get_window().size.x]
		if sig != last_sig:
			last_sig = sig
			_update_view()
			_update_coords()
		_update_status()

	label_timer += delta
	if label_timer >= 0.12:
		label_timer = 0.0
		_layout_labels()

	clock_timer += delta
	if clock_timer >= 1.0:
		clock_timer = 0.0
		_update_clock()

	mm_timer += delta
	if mm != null and mm_timer >= 0.1:
		mm_timer = 0.0
		mm.queue_redraw()
	if poi != null:
		poi.queue_redraw()

func _fmt_ll(lat: float, lon: float) -> String:
	var ns := "N"
	if lat < 0.0:
		ns = "S"
	return "%.2f° %s, %.2f° E" % [absf(lat), ns, fposmod(lon, 360.0)]

func _update_coords() -> void:
	if coord_label == null:
		return
	var p := get_global_mouse_position()
	var lon := (p.x + ox) / world_w * 360.0 - 180.0
	var lat := 90.0 - (p.y + oy) / world_h * 180.0
	if absf(lat) <= 90.0:
		coord_label.text = _fmt_ll(lat, lon)

func _update_scale() -> void:
	if scale_line == null:
		return
	var m_per_world := 360.0 / (TILE * pow(2.0, WORLD_Z + 1)) * KM_PER_DEG * 1000.0
	var mpp := m_per_world / cam.zoom.x
	var target := mpp * 120.0
	var mag := pow(10.0, floor(log(target) / log(10.0)))
	var nice := mag
	for m in [1.0, 2.0, 5.0, 10.0]:
		if mag * m <= target:
			nice = mag * m
	scale_line.custom_minimum_size.x = nice / mpp
	if nice >= 1000.0:
		scale_lbl.text = "%d km" % int(round(nice / 1000.0))
	else:
		scale_lbl.text = "%d m" % int(nice)

# ---------------- Mars time ----------------
func _msd() -> float:
	var unix := Time.get_unix_time_from_system()
	var jd_ut := unix / 86400.0 + 2440587.5
	var jd_tt := jd_ut + (37.0 + 32.184) / 86400.0
	return (jd_tt - 2451549.5) / 1.0274912517 + 44796.0 - 0.0009626

func _mars_lmst(lon_east: float) -> float:
	var mtc := fposmod(_msd(), 1.0) * 24.0
	return fposmod(mtc + lon_east / 15.0, 24.0)

func _update_clock() -> void:
	if clock_label == null:
		return
	var h := _mars_lmst(0.0)
	var utc := Time.get_time_dict_from_system(true)
	clock_label.text = "MARS MTC %02d:%02d   |   EARTH UTC %02d:%02d" % [int(h), int((h - int(h)) * 60.0), int(utc["hour"]), int(utc["minute"])]

func _est_temp(lat: float, h: float) -> float:
	var f := absf(lat) / 90.0
	var mean := -45.0 - 40.0 * f * f
	var amp := 35.0 - 15.0 * f
	return mean + amp * cos((h - 14.0) / 24.0 * TAU)

# ---------------- Tile streaming ----------------
func _key(li: int, z: int, col: int, row: int) -> int:
	return (((li << 5) | z) << 40) | (col << 20) | row

func _range(z: int, cx: float, cy: float, half: Vector2) -> Dictionary:
	var ts := float(TILE) * pow(2.0, WORLD_Z - z)
	var maxc := int(pow(2.0, z + 1)) - 1
	var maxr := int(pow(2.0, z)) - 1
	var c0 := clampi(int(floor((cx - half.x) / ts)), 0, maxc)
	var c1 := clampi(int(floor((cx + half.x) / ts)), 0, maxc)
	var r0 := clampi(int(floor((cy - half.y) / ts)), 0, maxr)
	var r1 := clampi(int(floor((cy + half.y) / ts)), 0, maxr)
	return {"c0": c0, "c1": c1, "r0": r0, "r1": r1, "n": (c1 - c0 + 1) * (r1 - r0 + 1)}

func _full_range(z: int) -> Dictionary:
	var maxc := int(pow(2.0, z + 1)) - 1
	var maxr := int(pow(2.0, z)) - 1
	return {"c0": 0, "c1": maxc, "r0": 0, "r1": maxr, "n": (maxc + 1) * (maxr + 1)}

func _retry(q: Dictionary, attempt: int) -> void:
	var st: Dictionary = layers[q["li"]]
	var node: Node2D = st["node"]
	if not node.visible:
		inflight.erase(q["key"])
		return
	_request(q, attempt)

func _is_failed(key: int) -> bool:
	if not failed.has(key):
		return false
	var t: int = failed[key]
	if t < 0:
		return true
	if Time.get_ticks_msec() - t > 15000:
		failed.erase(key)
		return false
	return true

func _tile_visible(sp: Sprite2D) -> bool:
	var zz := int(sp.get_meta("z"))
	return zz <= cur_z + MAX_BIAS + 1 or zz <= int(sp.get_meta("zmin"))

func _update_view() -> void:
	var half := vp_size / (2.0 * cam.zoom.x)
	var half_pf := half * PREFETCH
	var cx := cam.position.x + ox
	var cy := cam.position.y + oy
	cur_z = int(round(float(WORLD_Z) + log(cam.zoom.x) / log(2.0)))
	var eff_z := 0
	var best_max := 0
	var needed: Array = []

	for li in range(layers.size()):
		var st: Dictionary = layers[li]
		var node: Node2D = st["node"]
		if not node.visible:
			continue
		var def: Dictionary = st["def"]
		var cap := int(def["cap"])
		var zmin := int(st["min"])
		var zmax := int(st["max"])
		var z := mini(cur_z + int(def["bias"]), zmax)
		if z < zmin:
			if zmin - z > BELOW_MIN:
				continue
			z = zmin
		var rg := _range(z, cx, cy, half_pf)
		while int(rg["n"]) > cap and z > zmin:
			z -= 1
			rg = _range(z, cx, cy, half_pf)
		if int(rg["n"]) > cap:
			rg = _range(z, cx, cy, half)
			if int(rg["n"]) > cap * 5 / 4:
				continue
		eff_z = maxi(eff_z, z)
		best_max = maxi(best_max, zmax)

		var passes: Array = [{"z": z, "rg": rg}]
		if zmin <= BASE_Z:
			var zc := maxi(zmin, z - 2)
			if zc < z:
				passes.append({"z": zc, "rg": _range(zc, cx, cy, half_pf)})
			if BASE_Z < z:
				passes.append({"z": BASE_Z, "rg": _full_range(BASE_Z)})
		else:
			var zu := z - 1
			if zu >= zmin:
				passes.append({"z": zu, "rg": _range(zu, cx, cy, half_pf)})

		for ps in passes:
			var pz: int = ps["z"]
			var prg: Dictionary = ps["rg"]
			var ts := float(TILE) * pow(2.0, WORLD_Z - pz)
			for row in range(int(prg["r0"]), int(prg["r1"]) + 1):
				for col in range(int(prg["c0"]), int(prg["c1"]) + 1):
					var key := _key(li, pz, col, row)
					if tiles.has(key) or _is_failed(key) or inflight.has(key):
						continue
					var dx := (col + 0.5) * ts - cx
					var dy := (row + 0.5) * ts - cy
					needed.append({"key": key, "li": li, "z": pz, "col": col, "row": row, "d": dx * dx + dy * dy})

	if not needed.is_empty():
		needed.sort_custom(func(a, b): return a["z"] < b["z"] or (a["z"] == b["z"] and a["d"] < b["d"]))
	queue = needed

	_evict(half)

	if cur_z != last_cur_z:
		last_cur_z = cur_z
		for key in tiles:
			var sp2: Sprite2D = tiles[key]
			sp2.visible = _tile_visible(sp2)

	if res_label:
		var mpp := 360.0 / (256.0 * pow(2.0, eff_z + 1)) * KM_PER_DEG * 1000.0
		var txt := ""
		if mpp < 1.0:
			txt = "Detail ~%d cm/px" % int(round(mpp * 100.0))
		else:
			txt = "Detail ~%.1f m/px" % mpp
		if cur_z > best_max:
			txt += " (past data)"
			res_label.add_theme_color_override("font_color", ORANGE)
		else:
			res_label.add_theme_color_override("font_color", GREEN)
		res_label.text = txt

	_pump()

func _evict(half: Vector2) -> void:
	if tiles.size() <= TILE_CAP:
		return
	var cand: Array = []
	for key in tiles:
		var sp: Sprite2D = tiles[key]
		var zz := int(sp.get_meta("z"))
		if zz <= BASE_Z:
			continue
		var tsz := float(TILE) * pow(2.0, WORLD_Z - zz)
		var dx := maxf(absf(sp.position.x + tsz * 0.5 - cam.position.x) - tsz * 0.5, 0.0) / half.x
		var dy := maxf(absf(sp.position.y + tsz * 0.5 - cam.position.y) - tsz * 0.5, 0.0) / half.y
		var dd := maxf(dx, dy)
		if dd > PREFETCH + 0.4:
			cand.append([dd, key])
	cand.sort_custom(func(a, b): return a[0] > b[0])
	var target := int(TILE_CAP * 0.85)
	for c in cand:
		if tiles.size() <= target:
			break
		var sp3: Sprite2D = tiles[c[1]]
		sp3.queue_free()
		tiles.erase(c[1])

func _pump() -> void:
	while active < MAX_REQUESTS and not queue.is_empty():
		var q: Dictionary = queue.pop_front()
		var key: int = q["key"]
		if tiles.has(key) or _is_failed(key) or inflight.has(key):
			continue
		_request(q, 0)

func _cache_path(q: Dictionary) -> String:
	var st: Dictionary = layers[q["li"]]
	var def: Dictionary = st["def"]
	return "%s/%d_%d_%d_%d.tile" % [CACHE_DIR, int(str(def["id"]).hash()), q["z"], q["col"], q["row"]]

func _request(q: Dictionary, attempt: int) -> void:
	var key: int = q["key"]
	if USE_CACHE and attempt == 0 and not q.has("nocache"):
		var path := _cache_path(q)
		if FileAccess.file_exists(path):
			inflight[key] = true
			decoding += 1
			WorkerThreadPool.add_task(_decode_file.bind(path, q))
			return
	_http(q, attempt)

func _http(q: Dictionary, attempt: int) -> void:
	var st: Dictionary = layers[q["li"]]
	var exts := ["jpg", "png"]
	var ei := (int(st["ext"]) + attempt) % 2
	var def: Dictionary = st["def"]
	var url := "%s%s/1.0.0/default/default028mm/%d/%d/%d.%s" % [BASE, def["id"], q["z"], q["row"], q["col"], exts[ei]]
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = 15.0
	add_child(http)
	active += 1
	inflight[q["key"]] = true
	http.request_completed.connect(_on_tile.bind(http, q, attempt, ei))
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		active -= 1
		_fail(q, st)

func _on_tile(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, http: HTTPRequest, q: Dictionary, attempt: int, ei: int) -> void:
	http.queue_free()
	active -= 1
	var st: Dictionary = layers[q["li"]]
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 0:
		var path := ""
		if USE_CACHE:
			path = _cache_path(q)
		decoding += 1
		WorkerThreadPool.add_task(_decode.bind(body, q, ei, path))
		return
	var transient := result != HTTPRequest.RESULT_SUCCESS or code == 429 or code >= 500
	if transient:
		var tries := int(q.get("tries", 0))
		if tries < MAX_RETRIES:
			q["tries"] = tries + 1
			get_tree().create_timer(0.5 * (tries + 1)).timeout.connect(_retry.bind(q, attempt))
			_pump()
			return
	if not transient and not bool(st["confirmed"]) and attempt == 0:
		_http(q, 1)
		return
	_fail(q, st, code == 404 or code == 403)
	_pump()

func _decode(body: PackedByteArray, q: Dictionary, ei: int, path: String) -> void:
	var img := Image.new()
	var err := img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_png_from_buffer(body)
	var good := err == OK
	if good:
		img.generate_mipmaps()
		if path != "":
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(body)
				f.close()
	call_deferred("_decoded", img, good, q, ei)

func _decode_file(path: String, q: Dictionary) -> void:
	var body := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	var good := false
	if body.size() > 0:
		var err := img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_png_from_buffer(body)
		good = err == OK
	if good:
		img.generate_mipmaps()
		call_deferred("_decoded", img, true, q, -1)
	else:
		DirAccess.remove_absolute(path)
		call_deferred("_cache_bad", q)

func _cache_bad(q: Dictionary) -> void:
	decoding -= 1
	q["nocache"] = true
	_http(q, 0)

func _decoded(img: Image, good: bool, q: Dictionary, ei: int) -> void:
	decoding -= 1
	var st: Dictionary = layers[q["li"]]
	if good:
		if ei >= 0:
			st["ext"] = ei
			st["confirmed"] = true
		ready_tiles.append({"img": img, "q": q})
	else:
		_fail(q, st)
		_pump()

func _add_tile(item: Dictionary) -> void:
	var q: Dictionary = item["q"]
	var img: Image = item["img"]
	var st: Dictionary = layers[q["li"]]
	var def: Dictionary = st["def"]
	var key: int = q["key"]
	inflight.erase(key)
	if tiles.has(key):
		return
	var z: int = q["z"]
	var col: int = q["col"]
	var row: int = q["row"]
	var ts := float(TILE) * pow(2.0, WORLD_Z - z)
	var sp := Sprite2D.new()
	sp.texture = ImageTexture.create_from_image(img)
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.use_parent_material = true
	sp.centered = false
	sp.scale = Vector2(ts, ts) / Vector2(img.get_size())
	sp.position = Vector2(col * ts - ox, row * ts - oy)
	sp.z_index = z
	sp.set_meta("z", z)
	sp.set_meta("zmin", int(def["min"]))
	sp.visible = _tile_visible(sp)
	sp.modulate.a = 0.0
	var node: Node2D = st["node"]
	node.add_child(sp)
	var tw := sp.create_tween()
	tw.tween_property(sp, "modulate:a", 1.0, 0.25)
	tiles[key] = sp
	var okd: Dictionary = st["ok"]
	okd[z] = int(okd.get(z, 0)) + 1
	ok_total += 1

func _fail(q: Dictionary, st: Dictionary, permanent: bool = false) -> void:
	var key: int = q["key"]
	inflight.erase(key)
	if not permanent:
		failed[key] = Time.get_ticks_msec()
		return
	failed[key] = -1
	var z: int = q["z"]
	var bad: Dictionary = st["bad"]
	var okd: Dictionary = st["ok"]
	bad[z] = int(bad.get(z, 0)) + 1
	var def: Dictionary = st["def"]
	if bool(def["adapt"]) and int(okd.get(z, 0)) == 0 and int(bad[z]) >= 12 and z > int(st["min"]):
		st["max"] = mini(int(st["max"]), z - 1)
		last_sig = ""

func _update_status() -> void:
	if tile_status == null:
		return
	if layer_stats != null:
		var lines: Array = []
		for st in layers:
			var sdef: Dictionary = st["def"]
			var okn := 0
			for v in st["ok"].values():
				okn += int(v)
			var badn := 0
			for v2 in st["bad"].values():
				badn += int(v2)
			lines.append("%s: %d tiles, %d no-data" % [str(sdef["name"]).split(" (")[0], okn, badn])
		layer_stats.text = "\n".join(PackedStringArray(lines))
	var pending := queue.size() + active + decoding + ready_tiles.size()
	if pending > 0:
		tile_status.text = "Loading (%d)" % pending
		tile_status.add_theme_color_override("font_color", ORANGE)
	elif ok_total == 0:
		tile_status.text = "No tiles loaded"
		tile_status.add_theme_color_override("font_color", HAZ_RED)
	else:
		tile_status.text = "Imagery ready"
		tile_status.add_theme_color_override("font_color", GREEN)

# Whole-planet thumbnail for the overview map (two zoom-0 tiles)
func _load_mini() -> void:
	for col in range(2):
		_mini_req(col, 0)

func _mini_req(col: int, attempt: int) -> void:
	var exts := ["jpg", "png"]
	var url := "%sMars_Viking_MDIM21_ClrMosaic_global_232m/1.0.0/default/default028mm/0/0/%d.%s" % [BASE, col, exts[attempt]]
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_mini.bind(http, col, attempt))
	http.request(url)

func _on_mini(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, http: HTTPRequest, col: int, attempt: int) -> void:
	http.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var img := Image.new()
		var err := img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_png_from_buffer(body)
		if err == OK:
			mini_tex[col] = ImageTexture.create_from_image(img)
			if mm != null:
				mm.queue_redraw()
			return
	if attempt == 0:
		_mini_req(col, 1)

# ---------------- Places: visibility, labels, drawing ----------------
func _pin_r(p: Dictionary) -> float:
	var t: int = p["tier"]
	if t == 1:
		return 9.0
	if t == 2:
		return 8.0
	return 7.0

func _matches(p: Dictionary) -> bool:
	if not bool(cat_on.get(p["cat"], true)):
		return false
	if query == "":
		return true
	var q := query.to_lower()
	return str(p["name"]).to_lower().contains(q) or str(p["cat"]).to_lower().contains(q) or str(p["id"]).contains(q)

func _pin_visible(p: Dictionary, z: float) -> bool:
	if not bool(cat_on.get(p["cat"], true)):
		return false
	if bool(p["hide_local"]) and local_alpha > 0.5:
		return false
	if query != "":
		return _matches(p)
	var t: int = p["tier"]
	if t == 2:
		return z >= 0.07
	if t >= 3:
		return z >= 0.32
	return true

func _layout_labels() -> void:
	label_ok.clear()
	var font := ThemeDB.fallback_font
	var z := cam.zoom.x
	var items: Array = []
	var pin_rects: Array = []
	for i in prio_order:
		var p: Dictionary = places[i]
		var forced: bool = (i == sel_place or i == hover_place)
		if not forced and not _pin_visible(p, z):
			continue
		var sp := _s(p["pos"])
		if sp.x < -40.0 or sp.y < -40.0 or sp.x > vp_size.x + 40.0 or sp.y > vp_size.y + 40.0:
			continue
		var r := _pin_r(p)
		var item := {"i": i, "sp": sp, "r": r}
		var rect := Rect2(sp - Vector2(r + 2.0, r + 2.0), Vector2(r + 2.0, r + 2.0) * 2.0)
		if forced:
			items.insert(0, item)
			pin_rects.insert(0, rect)
		else:
			items.append(item)
			pin_rects.append(rect)
	var placed: Array = []
	for n in range(items.size()):
		var it: Dictionary = items[n]
		var p2: Dictionary = places[it["i"]]
		var w := font.get_string_size(str(p2["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		var sp2: Vector2 = it["sp"]
		var rr: float = it["r"]
		var lrect := Rect2(sp2.x + rr + 5.0, sp2.y - 9.0, w + 8.0, 18.0)
		var ok := true
		for m in range(pin_rects.size()):
			if m != n and lrect.intersects(pin_rects[m]):
				ok = false
				break
		if ok:
			for pr in placed:
				if lrect.intersects(pr):
					ok = false
					break
		if ok:
			label_ok[it["i"]] = true
			placed.append(lrect)

func _draw_pin(c: Control, sp: Vector2, p: Dictionary, r: float) -> void:
	var col: Color = p["color"]
	var ring: Color = p["ring"]
	c.draw_circle(sp + Vector2(0, 1.5), r + 2.5, Color(0, 0, 0, 0.45))
	c.draw_circle(sp, r + 1.8, ring)
	c.draw_circle(sp, r, col)
	var k: String = p["icon"]
	var w := Color.WHITE
	if k == "mission":
		c.draw_circle(sp, r * 0.38, w)
	elif k == "volcano":
		c.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -r * 0.55), sp + Vector2(r * 0.55, r * 0.42), sp + Vector2(-r * 0.55, r * 0.42)]), w)
	elif k == "canyon":
		c.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -r * 0.6), sp + Vector2(r * 0.45, 0), sp + Vector2(0, r * 0.6), sp + Vector2(-r * 0.45, 0)]), w)
	elif k == "basin":
		c.draw_arc(sp, r * 0.5, 0.0, TAU, 20, w, 1.6)
	elif k == "plain":
		c.draw_rect(Rect2(sp - Vector2(r * 0.38, r * 0.38), Vector2(r * 0.76, r * 0.76)), w)
	else:
		c.draw_line(sp + Vector2(-r * 0.5, 0), sp + Vector2(r * 0.5, 0), w, 1.8)
		c.draw_line(sp + Vector2(0, -r * 0.5), sp + Vector2(0, r * 0.5), w, 1.8)

func _draw_label(c: Control, font: Font, sp: Vector2, p: Dictionary, r: float) -> void:
	var pos := Vector2(sp.x + r + 7.0, sp.y + 4.0)
	var txt := str(p["name"])
	c.draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 4, Color(0, 0, 0, 0.9))
	c.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color.WHITE)

func draw_overlay(c: Control) -> void:
	var font := ThemeDB.fallback_font
	var z := cam.zoom.x
	_draw_nav(c)
	for i in draw_order:
		if i == sel_place or i == hover_place:
			continue
		var p: Dictionary = places[i]
		if not _pin_visible(p, z):
			continue
		var sp := _s(p["pos"])
		if sp.x < -40.0 or sp.y < -40.0 or sp.x > vp_size.x + 40.0 or sp.y > vp_size.y + 40.0:
			continue
		var r := _pin_r(p)
		_draw_pin(c, sp, p, r)
		if label_ok.has(i):
			_draw_label(c, font, sp, p, r)
	for i2 in [hover_place, sel_place]:
		if i2 < 0:
			continue
		var p2: Dictionary = places[i2]
		var sp2 := _s(p2["pos"])
		if sp2.x < -40.0 or sp2.y < -40.0 or sp2.x > vp_size.x + 40.0 or sp2.y > vp_size.y + 40.0:
			continue
		var r2 := _pin_r(p2) + 2.0
		if i2 == sel_place:
			var t := fposmod(anim_t, 1.6) / 1.6
			var col: Color = p2["color"]
			c.draw_arc(sp2, r2 + 4.0 + 18.0 * t, 0.0, TAU, 40, Color(col, 1.0 - t), 2.0)
		_draw_pin(c, sp2, p2, r2)
		_draw_label(c, font, sp2, p2, r2)
	# route endpoints
	for pair in [[nav_a, "A", GREEN], [nav_b, "B", HAZ_RED]]:
		var ni: int = pair[0]
		if ni < 0:
			continue
		var np: Dictionary = places[ni]
		var nsp := _s(np["pos"])
		var ncol: Color = pair[2]
		c.draw_circle(nsp + Vector2(0, -22), 11.0, Color(0, 0, 0, 0.6))
		c.draw_circle(nsp + Vector2(0, -22), 10.0, ncol)
		c.draw_string(font, nsp + Vector2(-4, -17), str(pair[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		c.draw_line(nsp + Vector2(0, -12), nsp, ncol, 2.0)

func _draw_nav(c: Control) -> void:
	if nav_segs.is_empty():
		return
	var carry := fposmod(anim_t * 55.0, 34.0)
	for seg in nav_segs:
		var sp := PackedVector2Array()
		for q in seg:
			sp.append(_s(q))
		if sp.size() < 2:
			continue
		c.draw_polyline(sp, Color(0, 0, 0, 0.8), 7.0, true)
		c.draw_polyline(sp, ORANGE, 4.0, true)
		for i in range(sp.size() - 1):
			var a := sp[i]
			var b := sp[i + 1]
			var sl := a.distance_to(b)
			if sl < 0.001:
				continue
			var d := carry
			while d <= sl:
				c.draw_circle(a.lerp(b, d / sl), 2.6, Color.WHITE)
				d += 34.0
			carry = d - sl

func draw_minimap(c: Control) -> void:
	var sz := c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.0, 0.01))
	for col in range(2):
		var tex: Texture2D = mini_tex[col]
		if tex != null:
			c.draw_texture_rect(tex, Rect2(sz.x * 0.5 * col, 0.0, sz.x * 0.5, sz.y), false)
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.25))
	for seg in nav_segs:
		var pl := PackedVector2Array()
		for q in seg:
			pl.append(_w2m(q, sz))
		if pl.size() >= 2:
			c.draw_polyline(pl, ORANGE, 2.0)
	for p in places:
		var col2: Color = p["color"]
		c.draw_circle(_w2m(p["pos"], sz), 2.2, col2)
	var half := vp_size / (2.0 * cam.zoom.x)
	var a := _w2m(cam.position - half, sz)
	var b := _w2m(cam.position + half, sz)
	c.draw_rect(Rect2(a, b - a), Color.WHITE, false, 1.5)
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(ORANGE, 0.6), false, 1.0)

func _w2m(p: Vector2, sz: Vector2) -> Vector2:
	return Vector2((p.x + ox) / world_w * sz.x, (p.y + oy) / world_h * sz.y)

func _on_mini_pick(pos: Vector2) -> void:
	var sz := mm.size
	var w := Vector2(pos.x / sz.x * world_w - ox, pos.y / sz.y * world_h - oy)
	anchor_active = false
	follow_rover = false
	pos_target = w

# ---------------- UI helpers ----------------
func _anchor_rect(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob

func _flat(bg: Color, radius: int, margin: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = Color(ORANGE, 0.5)
	b.set_border_width_all(1)
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	return b

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13
	t.set_color("font_color", "Label", Color.WHITE)
	for cls in ["Button", "OptionButton", "CheckBox"]:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(k, cls, Color.WHITE)
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.5))
	t.set_color("caret_color", "LineEdit", ORANGE)
	t.set_color("font_color", "PopupMenu", Color.WHITE)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, _flat(Color(0.35, 0.05, 0.04), 6, 8))
		t.set_stylebox("hover", cls, _flat(Color(0.55, 0.12, 0.03), 6, 8))
		t.set_stylebox("pressed", cls, _flat(Color(0.75, 0.25, 0.02), 6, 8))
		t.set_stylebox("focus", cls, _flat(Color(0.35, 0.05, 0.04), 6, 8))
	t.set_stylebox("normal", "LineEdit", _flat(Color(0.08, 0.01, 0.02), 8, 8))
	t.set_stylebox("focus", "LineEdit", _flat(Color(0.12, 0.02, 0.03), 8, 8))
	t.set_stylebox("panel", "PopupMenu", _flat(PANEL_DARK, 6, 6))
	t.set_stylebox("hover", "PopupMenu", _flat(Color(0.55, 0.12, 0.03), 4, 4))
	return t

func _lbl(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l

func _wrap(text: String, color: Color, size: int, w: float = 280.0) -> Label:
	var l := _lbl(text, color, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(w, 0)
	return l

func _head(text: String, color: Color) -> Label:
	return _lbl(text, color, 11)

func _line(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = Color(color, 0.45)
	return r

func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _toggle(text: String, on: bool, swatch: Color, sw_size: Vector2, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var sw := ColorRect.new()
	sw.custom_minimum_size = sw_size
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.color = swatch
	h.add_child(sw)
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(cb)
	h.add_child(c)
	return h

func _kv(k: String, v: String, vcol: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var kl := _lbl(k, DIM, 12)
	kl.custom_minimum_size = Vector2(98, 0)
	kl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	h.add_child(kl)
	var vl := _wrap(v, vcol, 12, 170.0)
	vl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vl)
	return h

# ---------------- UI ----------------
func _build_ui() -> void:
	# pins and routes (screen space) sit above the sharpen pass
	var pl := CanvasLayer.new()
	pl.layer = 2
	add_child(pl)
	poi = PoiView.new()
	poi.app = self
	pl.add_child(poi)

	var ui := CanvasLayer.new()
	ui.layer = 3
	add_child(ui)
	var uroot := Control.new()
	uroot.set_anchors_preset(Control.PRESET_FULL_RECT)
	uroot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uroot.theme = _make_theme()
	ui.add_child(uroot)

	# ---- top bar ----
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _flat(PANEL_DARK, 0, 10))
	_anchor_rect(top, 0, 0, 1, 0, 0, 0, 0, 52)
	uroot.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 14)
	top.add_child(th)
	th.add_child(_lbl(APP_NAME, ORANGE, 22))
	th.add_child(_lbl(APP_TAG, DIM, 11))
	th.add_child(_spacer())
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Search places, missions, volcanoes..."
	search_edit.clear_button_enabled = true
	search_edit.custom_minimum_size = Vector2(380, 0)
	search_edit.text_changed.connect(_on_search)
	search_edit.text_submitted.connect(_on_search_enter)
	th.add_child(search_edit)
	th.add_child(_spacer())
	clock_label = _lbl("", BLUE, 12)
	th.add_child(clock_label)

	# ---- left sidebar ----
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", _flat(PANEL, 10, 12))
	_anchor_rect(side, 0, 0, 0, 1, 12, 64, 332, -46)
	uroot.add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	side.add_child(sv)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	sv.add_child(tabs)
	var grp := ButtonGroup.new()
	var tab_names := ["Explore", "Layers", "Navigate"]
	for i in range(3):
		var tb := Button.new()
		tb.text = tab_names[i]
		tb.toggle_mode = true
		tb.button_group = grp
		tb.button_pressed = (i == 0)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.pressed.connect(_show_tab.bind(i))
		tabs.add_child(tb)
		tab_btns.append(tb)
	sv.add_child(_line(ORANGE))
	for i in range(3):
		var sc := ScrollContainer.new()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.visible = (i == 0)
		sv.add_child(sc)
		var body := VBoxContainer.new()
		body.custom_minimum_size = Vector2(274, 0)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 8)
		sc.add_child(body)
		tab_scrolls.append(sc)
		tab_bodies.append(body)

	# Explore tab
	var ex: VBoxContainer = tab_bodies[0]
	ex.add_child(_head("CATEGORIES", ORANGE))
	for cat in CATS:
		var cd: Dictionary = CATS[cat]
		ex.add_child(_toggle(cat, true, cd["color"], Vector2(12, 12), _on_cat.bind(cat)))
	ex.add_child(_line(ORANGE))
	list_count = _lbl("", DIM, 12)
	ex.add_child(list_count)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 2)
	ex.add_child(list_box)

	# Layers tab
	var ly: VBoxContainer = tab_bodies[1]
	ly.add_child(_head("MAP TYPE", BLUE))
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	ly.add_child(brow)
	var bgrp := ButtonGroup.new()
	var bnames := ["Satellite", "Relief", "Thermal"]
	for i in range(3):
		var bb := Button.new()
		bb.text = bnames[i]
		bb.toggle_mode = true
		bb.button_group = bgrp
		bb.button_pressed = (i == 0)
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bb.pressed.connect(_set_basemap.bind(i))
		brow.add_child(bb)
	ly.add_child(_head("DETAIL IMAGERY", BLUE))
	ly.add_child(_toggle("CTX detail (5 m)", true, BLUE, Vector2(12, 12), _on_ctx))
	ly.add_child(_toggle("HiRISE (Jezero only)", false, BLUE, Vector2(12, 12), _on_hirise))
	ly.add_child(_toggle("Elevation tint (MOLA)", false, BLUE, Vector2(12, 12), _on_tint))
	ly.add_child(_lbl("Detail strength", DIM, 12))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = 1.0
	sl.custom_minimum_size = Vector2(250, 18)
	sl.value_changed.connect(_on_strength)
	ly.add_child(sl)
	sharp_btn = _button("Sharpen: " + str(SHARP_NAMES[sharp_idx]), _cycle_sharp)
	ly.add_child(sharp_btn)
	layer_stats = _wrap("", DIM, 11, 260.0)
	ly.add_child(layer_stats)
	ly.add_child(_line(ORANGE))
	ly.add_child(_head("OVERLAYS", ORANGE))
	ly.add_child(_toggle("Lat/lon grid", true, SILVER, Vector2(12, 12), _on_grid))
	ly.add_child(_line(ORANGE))
	ly.add_child(_head("JEZERO OPERATIONS  (zoom in to see)", ORANGE))
	for g in overlay_nodes:
		var holder: Node2D = overlay_nodes[g]
		ly.add_child(_toggle(g, true, GROUPS[g]["color"], Vector2(12, 12), _set_vis.bind(holder)))
	ly.add_child(_head("ROUTES", GREEN))
	for rt in routes:
		var route: Route = rt
		ly.add_child(_toggle(route.title, true, route.color, Vector2(18, 5), _set_vis.bind(route)))
	ly.add_child(_wrap("Zones and conditions are illustrative, not official NASA data.", ORANGE, 11, 260.0))

	# Navigate tab
	var nv: VBoxContainer = tab_bodies[2]
	nv.add_child(_head("ROUTE PLANNER", GREEN))
	nv.add_child(_lbl("From", DIM, 12))
	from_opt = OptionButton.new()
	nv.add_child(from_opt)
	nv.add_child(_lbl("To", DIM, 12))
	to_opt = OptionButton.new()
	nv.add_child(to_opt)
	var sorted_ids: Array = range(places.size())
	sorted_ids.sort_custom(func(a, b): return str(places[a]["name"]) < str(places[b]["name"]))
	for i in sorted_ids:
		from_opt.add_item(str(places[i]["name"]), i)
		to_opt.add_item(str(places[i]["name"]), i)
	_opt_select(from_opt, _pi("perseverance"))
	_opt_select(to_opt, _pi("curiosity"))
	var nb := HBoxContainer.new()
	nb.add_theme_constant_override("separation", 6)
	nv.add_child(nb)
	var pb := _button("Plan route", _plan_route)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nb.add_child(pb)
	nb.add_child(_button("Swap", _swap_route))
	nb.add_child(_button("Clear", _clear_route))
	nav_info = _wrap("Pick two places and press Plan route.", Color.WHITE, 12, 260.0)
	nv.add_child(nav_info)
	nv.add_child(_wrap("Great-circle estimate. It ignores terrain, hazards and weather. Vehicles marked concept do not exist yet.", ORANGE, 11, 260.0))

	# ---- right: details drawer ----
	card_panel = PanelContainer.new()
	card_panel.add_theme_stylebox_override("panel", _flat(PANEL, 10, 14))
	_anchor_rect(card_panel, 1, 0, 1, 1, -352, 64, -12, -262)
	card_panel.visible = false
	uroot.add_child(card_panel)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	card_panel.add_child(cv)
	var chead := HBoxContainer.new()
	chead.add_theme_constant_override("separation", 8)
	card_dot = ColorRect.new()
	card_dot.custom_minimum_size = Vector2(12, 12)
	card_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chead.add_child(card_dot)
	card_chip = _lbl("", Color.WHITE, 12)
	chead.add_child(card_chip)
	chead.add_child(_spacer())
	chead.add_child(_button("X", _close_card))
	cv.add_child(chead)
	card_title = _wrap("", Color.WHITE, 20, 290.0)
	cv.add_child(card_title)
	card_sub = _wrap("", DIM, 12, 290.0)
	cv.add_child(card_sub)
	cv.add_child(_line(ORANGE))
	var csc := ScrollContainer.new()
	csc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	csc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(csc)
	var cb := VBoxContainer.new()
	cb.custom_minimum_size = Vector2(296, 0)
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.add_theme_constant_override("separation", 8)
	csc.add_child(cb)
	card_body = _wrap("", Color.WHITE, 13, 290.0)
	cb.add_child(card_body)
	card_rows = VBoxContainer.new()
	card_rows.add_theme_constant_override("separation", 5)
	cb.add_child(card_rows)
	card_tele = _wrap("", GREEN, 12, 290.0)
	card_tele.visible = false
	cb.add_child(card_tele)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	cb.add_child(acts)
	btn_zoom = _button("Zoom to", _card_zoom)
	acts.add_child(btn_zoom)
	btn_from = _button("Navigate from here", _card_from)
	acts.add_child(btn_from)
	btn_to = _button("Navigate to here", _card_to)
	acts.add_child(btn_to)
	play_btn = _button("Play rover", _toggle_play)
	play_btn.visible = false
	acts.add_child(play_btn)

	# ---- right: overview map ----
	var mp := PanelContainer.new()
	mp.add_theme_stylebox_override("panel", _flat(PANEL, 10, 10))
	_anchor_rect(mp, 1, 1, 1, 1, -352, -250, -12, -46)
	mp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	uroot.add_child(mp)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 4)
	mp.add_child(mv)
	mv.add_child(_head("OVERVIEW  (click or drag to move)", BLUE))
	mm = MiniMap.new()
	mm.app = self
	mm.custom_minimum_size = Vector2(316, 158)
	mm.picked.connect(_on_mini_pick)
	mv.add_child(mm)

	# ---- zoom controls ----
	var zc := VBoxContainer.new()
	zc.add_theme_constant_override("separation", 6)
	_anchor_rect(zc, 0, 1, 0, 1, 344, -190, 412, -54)
	zc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	uroot.add_child(zc)
	zc.add_child(_button("+", _zoom_in))
	zc.add_child(_button("-", _zoom_out))
	zc.add_child(_button("Planet", _view_planet))
	zc.add_child(_button("Jezero", _view_jezero))

	# ---- bottom bar ----
	var bot := PanelContainer.new()
	bot.add_theme_stylebox_override("panel", _flat(PANEL_DARK, 0, 6))
	_anchor_rect(bot, 0, 1, 1, 1, 0, -34, 0, 0)
	uroot.add_child(bot)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 14)
	bot.add_child(bh)
	coord_label = _lbl("", BLUE, 12)
	coord_label.custom_minimum_size = Vector2(200, 0)
	bh.add_child(coord_label)
	bh.add_child(VSeparator.new())
	scale_line = ColorRect.new()
	scale_line.color = Color.WHITE
	scale_line.custom_minimum_size = Vector2(80, 3)
	scale_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(scale_line)
	scale_lbl = _lbl("", Color.WHITE, 12)
	scale_lbl.custom_minimum_size = Vector2(56, 0)
	bh.add_child(scale_lbl)
	bh.add_child(VSeparator.new())
	res_label = _lbl("", GREEN, 12)
	res_label.custom_minimum_size = Vector2(170, 0)
	bh.add_child(res_label)
	bh.add_child(VSeparator.new())
	tile_status = _lbl("", ORANGE, 12)
	bh.add_child(tile_status)
	bh.add_child(_spacer())
	bh.add_child(_lbl("Drag: pan   Scroll: zoom   Click: details   Esc: close", DIM, 11))
	bh.add_child(VSeparator.new())
	bh.add_child(_lbl(CREDIT, Color(1, 1, 1, 0.55), 10))

	_update_scale()
	_update_status()

func _show_tab(i: int) -> void:
	for j in range(tab_scrolls.size()):
		var sc: ScrollContainer = tab_scrolls[j]
		sc.visible = (j == i)

func _set_vis(on: bool, n: CanvasItem) -> void:
	n.visible = on

func _on_cat(on: bool, cat: String) -> void:
	cat_on[cat] = on
	_refresh_list()

# ---------------- Explore list / search ----------------
func _on_search(text: String) -> void:
	query = text.strip_edges()
	_show_tab(0)
	tab_btns[0].button_pressed = true
	_refresh_list()

func _on_search_enter(_t: String) -> void:
	for i in range(places.size()):
		if _matches(places[i]):
			_select_place(i)
			return

func _refresh_list() -> void:
	if list_box == null:
		return
	for ch in list_box.get_children():
		ch.queue_free()
	var idxs: Array = []
	for i in range(places.size()):
		if _matches(places[i]):
			idxs.append(i)
	idxs.sort_custom(func(a, b):
		var ca := str(places[a]["cat"])
		var cb := str(places[b]["cat"])
		if ca != cb:
			return ca < cb
		return str(places[a]["name"]) < str(places[b]["name"]))
	list_count.text = "%d places" % idxs.size()
	for i in idxs:
		var p: Dictionary = places[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(10, 10)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.color = p["color"]
		row.add_child(sw)
		var b := Button.new()
		b.text = str(p["name"])
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.pressed.connect(_select_place.bind(i))
		row.add_child(b)
		list_box.add_child(row)

func _pi(id: String) -> int:
	for i in range(places.size()):
		if str(places[i]["id"]) == id:
			return i
	return 0

func _opt_select(o: OptionButton, place_i: int) -> void:
	o.select(o.get_item_index(place_i))

# ---------------- Details drawer ----------------
func _card_show(title: String, chip: String, chip_col: Color, sub: String, body: String, rows: Array) -> void:
	card_dot.color = chip_col
	card_chip.text = chip
	card_chip.add_theme_color_override("font_color", chip_col)
	card_title.text = title
	card_sub.text = sub
	card_body.text = body
	for ch in card_rows.get_children():
		ch.queue_free()
	for r in rows:
		var rc := Color.WHITE
		if r.size() > 2:
			rc = r[2]
		card_rows.add_child(_kv(str(r[0]), str(r[1]), rc))
	card_tele.visible = false
	if detail_tween != null:
		detail_tween.kill()
	card_panel.visible = true
	card_panel.modulate.a = 0.0
	detail_tween = create_tween()
	detail_tween.tween_property(card_panel, "modulate:a", 1.0, 0.25)

func _close_card() -> void:
	_stop_play()
	selected_route = null
	if sel_local != null and is_instance_valid(sel_local):
		sel_local.call("set_selected", false)
	sel_local = null
	sel_place = -1
	if not card_panel.visible:
		return
	if detail_tween != null:
		detail_tween.kill()
	detail_tween = create_tween()
	detail_tween.tween_property(card_panel, "modulate:a", 0.0, 0.2)
	detail_tween.tween_callback(func(): card_panel.visible = false)

func _drive_color(d: String) -> Color:
	if d == "GO":
		return GREEN
	if d == "CAUTION":
		return ORANGE
	return HAZ_RED

func _worse(a: String, b: String) -> String:
	if int(RANK[a]) >= int(RANK[b]):
		return a
	return b

func _zoom_for(p: Dictionary) -> float:
	if FOCUS_ZOOM.has(p["id"]):
		return float(FOCUS_ZOOM[p["id"]])
	var cd: Dictionary = CATS[p["cat"]]
	return float(cd["zoom"])

func _select_place(i: int) -> void:
	if sel_local != null and is_instance_valid(sel_local):
		sel_local.call("set_selected", false)
	sel_local = null
	_stop_play()
	selected_route = null
	sel_place = i
	var p: Dictionary = places[i]
	var rows: Array = []
	rows.append(["Coordinates", _fmt_ll(p["lat"], p["lon"]), Color.WHITE])
	for f in p["facts"]:
		var col := Color.WHITE
		if f[0] == "Status":
			col = p["ring"]
		rows.append([f[0], f[1], col])
	var h := _mars_lmst(float(p["lon"]))
	var day := h >= 6.0 and h < 18.0
	rows.append(["Local time", "%02d:%02d LMST  (%s)" % [int(h), int((h - int(h)) * 60.0), "daylight" if day else "night"], GOLD if day else BLUE])
	rows.append(["Est. temperature", "%d °C (estimate)" % int(round(_est_temp(float(p["lat"]), h))), BLUE])
	var cd: Dictionary = CATS[p["cat"]]
	_card_show(str(p["name"]), str(p["cat"]).to_upper(), p["color"], _fmt_ll(p["lat"], p["lon"]), str(p["info"]), rows)
	btn_zoom.visible = true
	btn_from.visible = true
	btn_to.visible = true
	play_btn.visible = false
	_fly_to(p["pos"], _zoom_for(p))

func _card_zoom() -> void:
	if sel_place >= 0:
		var p: Dictionary = places[sel_place]
		_fly_to(p["pos"], _zoom_for(p))
	elif sel_local != null and is_instance_valid(sel_local) and sel_local is Zone:
		var z: Zone = sel_local
		_fly_to(z.position, 150.0 / maxf(z.full_radius, 1.0))

func _card_from() -> void:
	if sel_place >= 0:
		_opt_select(from_opt, sel_place)
		_show_tab(2)
		tab_btns[2].button_pressed = true

func _card_to() -> void:
	if sel_place >= 0:
		_opt_select(to_opt, sel_place)
		_show_tab(2)
		tab_btns[2].button_pressed = true

func _conds_along(r: Route) -> Array:
	var out: Array = []
	for z in zones:
		if z.cond == "Clear" or z.cond == "Cold":
			continue
		if r.dist_to(z.home) < z.full_radius and not out.has(z.cond):
			out.append(z.cond)
	return out

func _show_zone(z: Zone) -> void:
	_stop_play()
	selected_route = null
	sel_place = -1
	var gd: Dictionary = GROUPS[z.group]
	var c: Dictionary = COND[z.cond]
	var drive := _worse(str(gd["min_drive"]), str(c["drive"]))
	var rows: Array = []
	rows.append(["Conditions", "%s, wind ~%d km/h (demo)" % [z.cond, int(c["wind"])], c["color"]])
	rows.append(["Drive status", drive, _drive_color(drive)])
	rows.append(["Area", "~%.1f km across" % (z.full_radius / px_per_km * 2.0), Color.WHITE])
	rows.append(["Coordinates", _fmt_ll(z.lat, z.lon), Color.WHITE])
	_card_show(z.title, str(gd["status"]), z.color, "Jezero operations", z.info, rows)
	btn_zoom.visible = true
	btn_from.visible = false
	btn_to.visible = false
	play_btn.visible = false

func _show_route(r: Route) -> void:
	_stop_play()
	selected_route = r
	sel_place = -1
	var conds := _conds_along(r)
	var drive := "GO"
	for cn in conds:
		drive = _worse(drive, str(COND[cn]["drive"]))
	if r.diff == "Hard":
		drive = _worse(drive, "CAUTION")
	var rows: Array = []
	rows.append(["Length", "%.1f km, %d waypoints" % [r.length_km, r.pts.size()], Color.WHITE])
	rows.append(["Est. drive", "~%d sols (demo)" % maxi(1, int(round(r.length_km / 0.45))), Color.WHITE])
	rows.append(["Difficulty", "%s, max slope ~%d°" % [r.diff, int(r.slope)], Color.WHITE])
	if conds.is_empty():
		rows.append(["Along route", "No dust or wind zones", GREEN])
	else:
		rows.append(["Along route", ", ".join(PackedStringArray(conds)), GOLD])
	rows.append(["Drive status", drive, _drive_color(drive)])
	rows.append(["Stops", " > ".join(PackedStringArray(r.names)), Color.WHITE])
	_card_show(r.title, r.status, r.color, "Jezero operations route", r.info + "\n" + r.note, rows)
	btn_zoom.visible = false
	btn_from.visible = false
	btn_to.visible = false
	play_btn.text = "Play rover"
	play_btn.visible = true

func _toggle_play() -> void:
	if selected_route == null:
		return
	if playing:
		_stop_play()
		return
	selected_route.progress = 0.0
	playing = true
	follow_rover = true
	anchor_active = false
	zoom_target = clampf(zoom_target, 25.0, 120.0)
	play_btn.text = "Stop"

func _stop_play() -> void:
	playing = false
	follow_rover = false
	if selected_route != null:
		selected_route.progress = -1.0
		selected_route.queue_redraw()
	if play_btn:
		play_btn.text = "Play rover"
	if card_tele:
		card_tele.visible = false

# ---------------- Navigation planner ----------------
func _vec(lat: float, lon: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * cos(lo), cos(la) * sin(lo), sin(la))

func _gc(lat1: float, lon1: float, lat2: float, lon2: float, n: int) -> Array:
	var a := _vec(lat1, lon1)
	var b := _vec(lat2, lon2)
	var om := acos(clampf(a.dot(b), -1.0, 1.0))
	var out: Array = []
	if om < 0.000001 or om > 3.1415:
		out.append(Vector2(lat1, lon1))
		out.append(Vector2(lat2, lon2))
		return out
	var so := sin(om)
	for i in range(n + 1):
		var t := float(i) / float(n)
		var v := a * (sin((1.0 - t) * om) / so) + b * (sin(t * om) / so)
		out.append(Vector2(rad_to_deg(asin(clampf(v.z, -1.0, 1.0))), rad_to_deg(atan2(v.y, v.x))))
	return out

func _compass(deg: float) -> String:
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[int(round(deg / 45.0)) % 8]

func _fmt_dur(hours: float) -> String:
	if hours < 1.0:
		return "%d min" % int(round(hours * 60.0))
	if hours < 48.0:
		return "%.1f h" % hours
	return "%.0f days (%d sols)" % [hours / 24.0, int(round(hours / 24.6597))]

func _plan_route() -> void:
	var ia := from_opt.get_selected_id()
	var ib := to_opt.get_selected_id()
	if ia < 0 or ib < 0 or ia == ib:
		nav_info.text = "Choose two different places."
		return
	var a: Dictionary = places[ia]
	var b: Dictionary = places[ib]
	var la1 := float(a["lat"])
	var lo1 := float(a["lon"])
	var la2 := float(b["lat"])
	var lo2 := float(b["lon"])
	var pts := _gc(la1, lo1, la2, lo2, 120)
	nav_segs.clear()
	var seg := PackedVector2Array()
	var prev_lon := 0.0
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for i in range(pts.size()):
		var ll: Vector2 = pts[i]
		if i > 0 and absf(ll.y - prev_lon) > 180.0:
			nav_segs.append(seg)
			seg = PackedVector2Array()
		var w := _ll(ll.x, ll.y)
		seg.append(w)
		mn = Vector2(minf(mn.x, w.x), minf(mn.y, w.y))
		mx = Vector2(maxf(mx.x, w.x), maxf(mx.y, w.y))
		prev_lon = ll.y
	nav_segs.append(seg)
	nav_a = ia
	nav_b = ib
	var d_km := acos(clampf(_vec(la1, lo1).dot(_vec(la2, lo2)), -1.0, 1.0)) * MARS_R_KM
	var p1 := deg_to_rad(la1)
	var p2 := deg_to_rad(la2)
	var dl := deg_to_rad(lo2 - lo1)
	var by := sin(dl) * cos(p2)
	var bx := cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
	var brg := fposmod(rad_to_deg(atan2(by, bx)), 360.0)
	var txt := "%s  >  %s\nDistance: %.0f km (great-circle)\nStart bearing: %03d° %s\n\nTravel time, non-stop:" % [a["name"], b["name"], d_km, int(brg), _compass(brg)]
	for m in TRAVEL_MODES:
		txt += "\n  %s: %s" % [m[0], _fmt_dur(d_km / float(m[1]))]
	nav_info.text = txt
	var zf := minf(vp_size.x * 0.45 / maxf(mx.x - mn.x, 1.0), vp_size.y * 0.55 / maxf(mx.y - mn.y, 1.0))
	_fly_to((mn + mx) * 0.5, clampf(zf, min_zoom, 20.0))

func _swap_route() -> void:
	var ia := from_opt.get_selected_id()
	var ib := to_opt.get_selected_id()
	_opt_select(from_opt, ib)
	_opt_select(to_opt, ia)
	if not nav_segs.is_empty():
		_plan_route()

func _clear_route() -> void:
	nav_segs.clear()
	nav_a = -1
	nav_b = -1
	nav_info.text = "Pick two places and press Plan route."

# ---------------- Camera moves ----------------
func _fly_to(p: Vector2, z: float) -> void:
	anchor_active = false
	follow_rover = false
	pos_target = p
	zoom_target = clampf(z, min_zoom, MAX_ZOOM)

func _view_planet() -> void:
	_fly_to(Vector2(world_w * 0.5 - ox, world_h * 0.5 - oy), min_zoom)

func _view_jezero() -> void:
	_fly_to(_ll(CRATER_CENTER.x, CRATER_CENTER.y), 9.0)

func _zoom_in() -> void:
	anchor_active = false
	pos_target = cam.position
	zoom_target = clampf(zoom_target * 1.8, min_zoom, MAX_ZOOM)

func _zoom_out() -> void:
	anchor_active = false
	pos_target = cam.position
	zoom_target = clampf(zoom_target / 1.8, min_zoom, MAX_ZOOM)

func _zoom_at(f: float) -> void:
	follow_rover = false
	anchor_world = get_global_mouse_position()
	anchor_off = (anchor_world - cam.position) * cam.zoom.x
	zoom_target = clampf(zoom_target * f, min_zoom, MAX_ZOOM)
	anchor_active = true

# ---------------- Input ----------------
func _hit_any(pw: Vector2) -> Dictionary:
	var sp := _s(pw)
	var z := cam.zoom.x
	var best := -1
	var bd := 1.0e9
	for i in range(places.size()):
		var p: Dictionary = places[i]
		if not _pin_visible(p, z):
			continue
		var d := _s(p["pos"]).distance_to(sp)
		if d <= _pin_r(p) + 6.0 and d < bd:
			bd = d
			best = i
	if best >= 0:
		return {"k": "place", "i": best}
	if local_root.visible and local_alpha > 0.3:
		var px := 1.0 / z
		var br: Route = null
		var best_rd := 12.0 * px
		for r in routes:
			if not r.is_visible_in_tree():
				continue
			var d2 := r.dist_to(pw)
			if d2 < best_rd:
				best_rd = d2
				br = r
		if br != null:
			return {"k": "route", "o": br}
		var bz: Zone = null
		var best_d := INF
		for zn in zones:
			if not zn.is_visible_in_tree():
				continue
			var d3 := zn.global_position.distance_to(pw)
			if d3 <= maxf(zn.radius, 10.0 * px) and d3 < best_d:
				bz = zn
				best_d = d3
		if bz != null:
			return {"k": "zone", "o": bz}
	return {"k": "none"}

func _update_hover() -> void:
	var h := _hit_any(get_global_mouse_position())
	var kind: String = h["k"]
	var np := -1
	var nl = null
	if kind == "place":
		np = h["i"]
	elif kind == "route" or kind == "zone":
		nl = h["o"]
	hover_place = np
	if hover_local != nl:
		if hover_local != null and is_instance_valid(hover_local):
			hover_local.call("set_hover", false)
		hover_local = nl
		if hover_local != null:
			hover_local.call("set_hover", true)
	if np >= 0 or nl != null:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _click(pw: Vector2) -> void:
	var h := _hit_any(pw)
	var kind: String = h["k"]
	if kind == "place":
		_select_place(h["i"])
		return
	if sel_local != null and is_instance_valid(sel_local):
		sel_local.call("set_selected", false)
	sel_local = null
	if kind == "route":
		var r: Route = h["o"]
		sel_local = r
		r.set_selected(true)
		sel_place = -1
		_show_route(r)
		r.reveal = 0.0
		var tw := create_tween()
		tw.tween_property(r, "reveal", 1.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in r.pts:
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
		var zf := minf(vp_size.x * 0.35 / maxf(mx.x - mn.x, 1.0), vp_size.y * 0.5 / maxf(mx.y - mn.y, 1.0))
		_fly_to((mn + mx) * 0.5, zf)
	elif kind == "zone":
		var z: Zone = h["o"]
		sel_local = z
		z.set_selected(true)
		_show_zone(z)
		_fly_to(z.position, 150.0 / maxf(z.full_radius, 1.0))
	else:
		_close_card()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if e.pressed:
					dragging = true
					press_pos = e.position
				else:
					dragging = false
					if e.position.distance_to(press_pos) < 4.0:
						_click(get_global_mouse_position())
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(1.3)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(1.0 / 1.3)
	elif e is InputEventMouseMotion:
		_update_coords()
		if dragging:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				follow_rover = false
				anchor_active = false
				cam.position -= e.relative / cam.zoom.x
				pos_target = cam.position
			else:
				dragging = false
		else:
			_update_hover()
	elif e is InputEventKey and e.pressed:
		if e.keycode == KEY_ESCAPE:
			_close_card()
		elif e.keycode == KEY_HOME:
			_view_planet()
