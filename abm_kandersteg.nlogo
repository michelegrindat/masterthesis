;; Basic Model Structure for Flood Evacuation Model of Lake Oeschinen Flood Wave ;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Prelimnary Tasks ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; load extensions
extensions [ gis csv ] ;csv is only needed for stack overflow, might delete it later

;; define globals
globals [
  elevation-dataset
  streets-dataset
  streets-dataset-raster
  buildings-dataset
  buildings-dataset-raster
  flood-dataset-shp
  flood-dataset-raster
  test ; used for general testing of elements
  min-elevation
  max-elevation
  exit-patches
  evacuated
  stuck
  causalities
  isolated
  possible-patches-next-to-fire-station
  num-coordinators-evacuees
  num-of-residents
  resident ; used for assigning the household (workaround!)
  m f ; used for assigning age groupe to evacuees
  household-list
  evacuees-in-per
  no-of-households
  geb-id-list-1
  geb-id-list-2
  geb-id-list-3
  geb-id-list-csv
  a b x y z ; counters
  patches-with-geb-id
  people-per-household
  street-next-to-exit
  choices
  previous-patch
  next-patch
  houses-to-evacuate
  counter
  ; related to flood layers
  flood-counter
  flood-6000
  flood-6600
  flood-7200
  flood-7800
  flood-8400
  flood-9000
  flood-9600
  counter-since-flood
  ; counters for result generation
  warned-by-flood
  evacuated-by-car
  ; DEFINED ON THE INTERFACE:
  ; number-of-evacuees
  ; number-of-coordinators
  ; debug?
  ; mode ["day" "night"]
  ; background display ["elevation" "buildings"]
  ; obedience-order
  ; obedience-confirmation
  ; evacuees-in-panic
  ; alarm-mode [ "none" "sirens" "coordinators" "sirens + coordinators"
  ;                 "sirens + word of mouth" "coordinators word of mouth" "combination"
  ; prewarning-time
  ; receive-alarm
  ; alarm-length
  ; size-of-patches
]

;; define breeds
breed [ coordinators coordinator ]
breed [ evacuees evacuee ]
breed [ cars car ]

;; define variables
patches-own [
  elevation
  street
  slope
  underground
  geb-id
  geb-type
  residents
  workers
  households
  flooded?
  water-depth
  elevation-current
  exit?
  street-next-to-exit?
  anchor?

]

evacuees-own [
; static properties
  sex
  age
  hh-in-perimeter?
  household
  vehicle
  geb-id-e
  ob-order
  ob-conf
  last-patch-evacuee


; dynamic properties
 flood-perception
 wom-spreader?
 alarm-rank
 warned?
 alarm-type
 car-pref
 in-panic?
 evacuating?
 isolated?
 evacuation-point
 goal
 in-car?


]

coordinators-own [
next-evacuation-house
evacuation-point
geb-id-c
next-patch-cor
isolated?
]

cars-own [
car-id
seats
evacuees-no
evacuation-point
last-patch-car
next-patch-car
evacuee-panicking-in-car?
stuck?
evacuated?
]

; ---------------------------------------------------------------------------------------------------------------
;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; SETUP COMMMANDS ;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;
to setup

clear-all
reset-ticks

;; PATCH SETUP ;;
setup-elevation
setup-streets-shp
setup-streets-raster
setup-buildings-shp
setup-buildings-raster
setup-patches



;; TURTLE SETUP ;;
setup-evacuees-and-cars
if alarm-mode = "coordinators" OR alarm-mode = "sirens + coordinators" OR alarm-mode = "coordinators + word of mouth" OR alarm-mode = "combination" [
    setup-coordinators
  ]
; setup-cars ; wird nicht gebraucht, da setup im Zuge mit den Evacuees geschieht

;; GLOBAL SETUP;;
setup-globals

;; TESTING ;;

;test-something

end

; ---------------------------------------------------------------------------------------------------------------
;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;; GO COMMANDS ;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;
to go
;  tick
  ; by putting the tick at the beginning it will be accurate to calculate with it:
  ; 1 at the 1st timestep, 2 at the 2nd and so on.
  ; but this means that in the view you can always just see the state of the model at the beginning of the procedure

;; LOAD THE FLOOD LAYERS ;;
; to start updading patches as soon as the flood layers are loaded
update-patches

;; TESTING ;;
;test-it


;; COORDINATOR'S ROUTINE ;;
if alarm-mode = "coordinators" OR alarm-mode = "sirens + coordinators" OR alarm-mode = "coordinators + word of mouth" OR alarm-mode = "combination" [
  repeat 84 [
    handle-coordinators
    ask coordinators with [isolated? = false] [
      if not any? houses-to-evacuate and ticks > 1 [ ;if there are no houses to warn left
         ; evacuate yourself
          find-route-foot
          move-by-foot
        ]
      ]
   ]
]

;; EVACUEE'S ROUTINE ;;
 ask n-of (round (count evacuees with [ evacuating? = false ] * receive-alarm )) evacuees with [ evacuating? = false ] [ ; ev. ändern, dass aus allen ausgewählt wird und nicht nur aus denen die nicht evakuieren
    if alarm-mode = "sirens" OR alarm-mode = "sirens + coordinators" OR alarm-mode = "sirens + word of mouth" OR alarm-mode = "combination" and isolated? = false [
        receive-fw
      ]
    ]
 decide-evacuate

repeat 84 [ ; assumption that they walk 200 m in 10 minutes
    if alarm-mode = "word of mouth" OR alarm-mode = "sirens + word of mouth" OR alarm-mode = "coordinators + word of mouth" OR alarm-mode = "combination" [
        ask evacuees with [evacuating? = true and wom-spreader? = true] [
          ; print "this is working!"
           if any? evacuees in-radius 5 [
            ask other evacuees in-radius 5 [
              receive-ifw
            ]
          ]
        ]
  ]

  decide-transportation

  ask evacuees with [evacuating? = true and in-car? = false and isolated? = false] [
      find-route-foot
      move-by-foot
      dying
    ]
  pick-up-evacuee ; integrate the picking-up process in the evacuees loop, otherwise evacuees will always walk past the cars
]
; random movement for people in perimeter (remove to reduce model run time)
; ask evacuees with [hh-in-perimeter? = false and evacuating? = false] [
;  repeat 84 [
;    move-to one-of neighbors with [underground = "open" OR underground = "street"]
;  ]
;]
;; CAR'S ROUTINE ;;
  repeat 500 [ ; assumption that they drive 30 km/h
    find-route-car
    move-by-car
  ]
;; EVACUATING, DYING AND GETTING STUCK ;;
; Includes not only dying porcedure, but also getting evacuated or being isolated
dying
;; TESTING ;;
; test-it

tick

end
; ---------------------------------------------------------------------------------------------------------------
;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;; SETUP PROCEDURES ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup-elevation
;; ELEVATION-DATASET RASTER ;;
  ; loads elevation data into NetLogo and stores the information as a global variable
  ; change directory depending on where you are working!
  ;; for mac
  ; set elevation-dataset gis:load-dataset "/Volumes/GoogleDrive/My Drive/01_Masterarbeit/Data/abm_data_pool/dem_2m_dev_wgs84.asc"
  ;; for windows
   set elevation-dataset gis:load-dataset "D:/abm_data_input/dem_2m_dev_wgs84.asc"
end

to setup-streets-shp
;; STREETS-DATASET SHP ;;
  ; loads streets shapefile into NetLogo and stores the information as a global variable
  ; change directory depending on where you are working!
  ;; for mac
  ; set streets-dataset gis:load-dataset "/Volumes/GoogleDrive/My Drive/01_Masterarbeit/Data/abm_data_pool/streets_dev_wgs84_n.shp"
  ;; for windows
   set streets-dataset gis:load-dataset "D:/abm_data_pool/streets_dev_wgs84_n.shp"
  ; set the extent of the world to the extent of the streets
   gis:set-world-envelope (gis:envelope-of streets-dataset)


end

to setup-streets-raster
;; STREETS-DATASET RASTER ;;
  ; loads streets raster into NetLogo and stores the information as a global variable
  ; change directory depending on where you are working!
  ;; for mac
  ; set streets-dataset-raster gis:load-dataset "/Volumes/GoogleDrive/My Drive/01_Masterarbeit/Data/abm_data_pool/streets_dev_wgs84.asc"
  ;; for windows
   set streets-dataset-raster gis:load-dataset "D:/abm_data_input/streets_dev_wgs84.asc"
   gis:apply-raster streets-dataset-raster street

end

to setup-buildings-shp
;; GWS-TLM-DATASET SHP ;;
  ; loads gws-tlm shapefile into NetLogo and stores the information as a global variable
  ; change directory depending on where you are working!
  ;; for mac
 ; set buildings-dataset gis:load-dataset "/Volumes/GoogleDrive/My Drive/01_Masterarbeit/Data/abm_data_pool/tlm_gws_update_dev_wgs84.shp"
  ;; for windows
   set buildings-dataset gis:load-dataset "D:/abm_data_input/tlm_gws_update_dev_wgs84.shp"

end


to setup-buildings-raster
;; GWS-TLM-DATASET RASTER;;
  ; loads gws-tlm-dataset raster into NetLogo and stores the information as a global variable
  ; change directory depending on where you are working!
  ;; for mac
  ; set buildings-dataset-raster gis:load-dataset "/Volumes/GoogleDrive/My Drive/01_Masterarbeit/Data/abm_data_pool/tlm_gws_dev_wgs84.asc"
  ;; for windows
   set buildings-dataset-raster gis:load-dataset "D:/abm_data_input/tlm_gws_dev_wgs84.asc"

end

to setup-flood-raster

set flood-dataset-raster gis:load-dataset "D:/abm_data_pool/flood_dev_6000_wgs84_2.asc"

end

to setup-patches
  ; set patch size based on chooser on interface (the number determines how many pixels on the screen one patch inhabits)
  ifelse size-of-patches = 1 [set-patch-size 1] [set-patch-size 2]
  ; set-patch-size 1
  ;; DEFINE STATIC PROPERTIES ;;
  ask patches [set elevation -1]
  ; read the raster values (stores values of "elevation-dataset" into the patch-variable "elevation")
  gis:apply-raster elevation-dataset elevation
  gis:apply-raster streets-dataset-raster street
  ; gis:apply-raster flood-dataset-raster water-depth
  ; read the shapefilevalues (stores values of "buildings-dataset" into the different patch-variables)

  ; gis:apply-coverage flood-dataset-shp "TESTING" water-depth
  gis:set-coverage-maximum-threshold 10
  gis:apply-coverage buildings-dataset "GEB_ID" geb-id
  gis:apply-coverage buildings-dataset "G_KATS" geb-type
  gis:apply-coverage buildings-dataset "G_PTOALL" residents
  gis:apply-coverage buildings-dataset "GALLEMPTOT" workers
  gis:apply-coverage buildings-dataset "G_WHG" households


 ; define the underground of the patch
  ask patches [
    set underground (ifelse-value
      geb-type = -9999 OR geb-type = 0 ["building"]
      geb-type = 1021 OR geb-type = 1025 ["dwelling-fully"]
      geb-type = 1030 ["dwelling-mainly"]
      geb-type = 1040 ["dwelling-partially"]
      street = 1 OR street = 2 ["street"]
      water-depth > 0 ["water"]
      ["open"]
    )
  ]
; set patch color
; patch color depending on the chooser "background-display" on the interface

if background-display = "vectordata"
  [ask patches [

    gis:set-drawing-color brown
    gis:draw buildings-dataset 1
    gis:fill buildings-dataset 1
    gis:set-drawing-color brown - 3
    gis:draw streets-dataset 1
    ]
  ]

if background-display = "rasterdata" [
  ask patches [
    ;gis:set-drawing-color blue
    ;gis:draw flood-shp 1
    set pcolor (ifelse-value
      underground = "building" [violet]
      underground = "dwelling-fully" [violet]
      underground = "dwelling-mainly" [violet]
      underground = "dwelling-partially" [violet]
      underground = "street" [black]
      [gray + 4]
    )
  ]
]

if background-display = "rasterdata + elevation"
   [ ask patches [
       set pcolor (ifelse-value
         underground = "building" [orange]
         underground = "dwelling-fully" [violet]
         underground = "dwelling-mainly" [violet]
         underground = "dwelling-partially" [violet]
         [elevation]
         ; following line do not work yet (trying to make the elevation data into a black and white scale)
         ; ask patches [set pcolor (scale-color black elevation gis:minimum-of elevation-dataset gis:maximum-of elevation-dataset)]
       )
      ]
    ]

; patches on the edges will be set red and set as exits
  ask patches [
    ifelse count neighbors != 8 [
    ; ifelse elevation = -3.4 ; code to check how far the layer stretches
    set exit? true
    set pcolor red
    ] [
    set exit? false
    ]
]
  ; set up the fire station
  ; the location of the fire station is added manually here.
  ; there would of course be the option to load a layer with the station
  ; but this solution needs less calculation power
  ask patches at-points [
    [-222 -27] [-221 -27] [-220 -27] [-219 -27] [-218 -27] [-217 -27] [-216 -27]
    [-222 -28] [-221 -28] [-220 -28] [-219 -28] [-218 -28] [-217 -28] [-216 -28]
    [-222 -29] [-221 -29] [-220 -29] [-219 -29] [-218 -29] [-217 -29] [-216 -29]
    [-222 -30] [-221 -30] [-220 -30] [-219 -30] [-218 -30] [-217 -30] [-216 -30]
               [-221 -31] [-220 -31] [-219 -31] [-218 -31] [-217 -31] [-216 -31]
               [-221 -32] [-220 -32] [-219 -32] [-218 -32] [-217 -32] [-216 -32]
  ]
    [ set underground "fire station"
      set pcolor blue
    ]

;; DEFINE DYNAMIC PROPERTIES AT t = O ;;
  ask patches [
  set flooded? false
  set elevation-current elevation
  set water-depth 0
  set street-next-to-exit? false
  ]

end


to setup-evacuees-and-cars

if debugging-setup = true [
;; CREATE EVACUEES;;
;; create evacuees based on the number of the slider in the interface
create-evacuees number-of-evacuees

; hh-in-perimeter?
; already define this static property here, because it is important for the distribution of the evacuees
set evacuees-in-per n-of (number-of-evacuees * ratio-residents-externals) evacuees
ask evacuees-in-per [set hh-in-perimeter? true]
ask evacuees [if not member? self evacuees-in-per [set hh-in-perimeter? false]]

; place them on the patches depending on the mode (day/night)
; night mode: devide the evacuees in two groups.
; evacuees-in-buildings will make up for 90% and are asked to move to a patch that has "building" as underground
; the other evacuees account for 10% and are asked to move to a patch that has "open" as underground
ifelse mode = "night" [
  ; print "I am in night mode"
  ask evacuees-in-per [
    move-to one-of patches with [underground = "dwelling-fully" OR underground = "dwelling-mainly" OR underground = "dwelling-partially"]
    ]
  ask evacuees [if not member? self evacuees-in-per [
    move-to one-of patches with [underground = "open"]
    ]
  ]
]
; day mode: set the evacuees up on a random place of the bord
[
 ; print "I am in day mode"
  ask evacuees [
    move-to one-of patches
    ]
  ]
] ; end bracket for "if debugging-setup = true"

if debugging-setup = false [
    ;; CREATE EVACUEES AND ASSIGN GEB-ID-E
; set geb-id-list-2 remove-duplicates geb-id-list-1
 ;; for mac
 ; set geb-id-list-csv csv:from-file "/Volumes/GoogleDrive/My Drive/01_Masterarbeit/Data/abm_data_pool/geb-id-list-reduced.csv"
 ;; for windows
 set geb-id-list-csv csv:from-file "D:/abm_data_input/geb-id-list-reduced.csv" ; reads the geb-id values from a csv file to a list of lists (creating list directly out of NL created weird numbers)
 set geb-id-list-csv reduce sentence geb-id-list-csv ; reduces the list of lists to just one list
 set x 0 ; counter
 repeat length geb-id-list-csv [ ; repeat the process for every entry in the geb-id-list-csv
      if any? patches with [geb-id = item x geb-id-list-csv] [ ; check only for patches that have a geb-id (remove "NAN" and "-3.4" values)
      ask one-of patches with [geb-id = item x geb-id-list-csv] [ ; ask one of the patches with the same geb-id as the 1st, 2nd, 3rd and so on item in the geb-id list
        set anchor? true] ; to set the anchor to true (in order to use the variable as a divder for the agentset)
        set x x + 1 ; increase the counter by one
      ]
     ]
 ask patches with [anchor? = true] [ ; ask all the anchor patches
    sprout-evacuees residents [ ; to sprout the number of residents of their building
    set hh-in-perimeter? true
    set geb-id-e geb-id
    set household geb-id ; quick fix bc household couldn't get assigned properly yet. So no, every building counts as one household
    ]
 ]
ask evacuees [
      move-to one-of patches with [geb-id = [geb-id-e] of myself AND anchor? = true] ; distributes the evacuees within their building
    ]
; define number of non-residents
set num-of-residents sum [residents] of patches with [anchor? = true]
create-evacuees (num-of-residents / (ratio-residents-externals * 100)) * ((1 - ratio-residents-externals) * 100) [
      move-to one-of patches with [underground = "open"]
      set hh-in-perimeter? false
    ]

] ; end bracket for "if debugging-setup = false"


;; DEFINE FEATURES ;;
  ask evacuees [
    ; set shape "circle"
    set color green
    set size 6
    set isolated? false
  ]

;; DEFINE STATIC PROPERTIES ;;
 ; sex
 ; sex distribution of Kandersteg from 2015 (51.3 % female and 48,7% male) according to BFS
  let women n-of (count evacuees * 0.513) evacuees
  ask women [set sex "female"]
  ask evacuees [if not member? self women [set sex "male"]]

; age
; age assignment for men
 ask evacuees [ set age -1 ]
 let i 0
 let prop-m (list 0.11 0.04 0.26 0.27 0.06 0.26) ; age distribution according to BFS (2015)
 let age-group-m (list "0-14" "15-19" "20-39" "40-59" "60-64" "65+")
 repeat 5 [ ; repeasts the following code 5 times
 set m evacuees with [age = -1 AND sex = "male"] ; set m to the no. of male evacuees with age -1
    ask n-of (round(count evacuees with [ sex = "male"]) * item i prop-m) m [ ;ask the number of men from the 1st age category
      set age item i age-group-m                                              ; to set the age to the corresponding age group
    ]
    set i i + 1 ; increment by one after each iteration, so that in the next repetition a different proportion and a different
                ; age group is called
  ]
  ask m [set age "65+"]  ; ask the remaining agents to set the age to 65+
                         ; do not loop 6 times instead, bc this leads to rounding mistakes, even with round function in place
; age assignemt for women (same process as for men, but with other proportions for age cateogries)
let v 0
let prop-f (list 0.11 0.05 0.24 0.27 0.07 0.26)
let age-group-f (list "0-14" "15-19" "20-39" "40-59" "60-64" "65+")  ; age distribution according to BFS (2015)
repeat 5[
        set f evacuees with [age = -1 AND sex = "female"]
   ask n-of (round(count evacuees with [ sex = "female"]) * item i prop-m) m [
     set age item i age-group-m
    ]
   set v v + 1
  ]
ask f [set age "65+"]

;; SETUP CAR ;;
; procedure only used when debugging!
  ask patches with [anchor? = true] [
    sprout-cars round (households * 1.38) [ ; 1.38 = no. of cars per household
      set color brown
      set shape "car"
      set size 7
    ; max. number of seats per car
    set seats 5
    ; number of evacuees present in car
    set evacuees-no 0
    set stuck? false
    set evacuated? false
    set evacuee-panicking-in-car? false
    set last-patch-car []
    set evacuation-point 0

      set car-id geb-id ; simplification because each building is seen as one household
      let target-patch min-one-of patches with [underground = "street" and [underground] of one-of neighbors = "street"] [distance myself]
      move-to target-patch
    ]
  ]

 ; obedience-order
  ; calculate the number of evacuees that will be obedient based on the percentage given in the interface
  let obedient-evacuees n-of (count evacuees * obedience-order) evacuees
  ask obedient-evacuees [set ob-order "obedient"]
  ; if evacuee is not part of the obedient evacuees, set obedience order to non-obedient
  ask evacuees [if not member? self obedient-evacuees [set ob-order "non-obedient"]]

 ; obedience-confirmation
  ; obedient-evacuees-2 are calculated by multiplying number pool of evacuees that were not obedient in the 1st round
  ; with the percentage of obedience-confirmation on the interface
 let obedient-evacuees-2 n-of (count evacuees with [ob-order = "non-obedient"] * obedience-confirmation) evacuees with [ob-order = "non-obedient"]
; assign ob-order based on 1. if already obedient, 2. obedient in 2nd round 3. not obediant
 ask evacuees [
    set ob-conf (ifelse-value
    member? self obedient-evacuees ["not-rel"]
    member? self obedient-evacuees-2 ["obedient"]
    ["non-obedient"])
]

;; DEFINE DYNAMIC PROPERTIES AT t = O ;;

ask n-of (count evacuees * word-of-mouth-spreaders) evacuees [
    set wom-spreader? true
  ]
ask evacuees [
    if wom-spreader? != true [
      set wom-spreader? false
    ]
  ]

  ask evacuees [
    set evacuating? false
    set in-panic? false   ; panicking?
    set in-car? false
    set warned? false
    set alarm-rank 0    ; alarm-rank
    set alarm-type ""   ; alarm-type
    set car-pref 0
  ]

end




to setup-coordinators
  ; create coordinators based on the slider
  ; set size and color, move to the fire station
  create-coordinators number-of-coordinators [
  ; DEFINE PROPERTIES
  set shape "default"
  set size 6
  set color blue
  set next-evacuation-house 0
  set isolated? false
  move-to one-of patches with [underground = "fire station"]
  ]

end

to setup-cars
 ; WIRD IM MOMENT NICHT VERWENDET DA CARS DURCH GEB-ID KREIRT WERDEN IM EVACUEE SETUP
; create cars based on the slider
create-cars number-of-cars [
    set shape "car"
    set size 5
    set color brown
    ;
  ]

; DEFINE DYNAMIC PROPERTIES AT t = 0

ask cars [
    ; max. number of seats per car
    set seats 5
    ; number of evacuees present in car
    set evacuees-no 0
    set stuck? false
    set evacuated? false
    set evacuee-panicking-in-car? false
    ; set last-patch-car []
    set last-patch-car 0
]

end

to setup-globals

set exit-patches patches with [exit? = true]
ask exit-patches [
    ask neighbors with [underground = "street"] [
     set street-next-to-exit? true
    ]
]
set street-next-to-exit patches with [street-next-to-exit? = true ]

; set the total amount of evacuees and coordinators
; to be able to define when the model should stop
; (when all of them are either evacuated, dead or isolated)
set num-coordinators-evacuees count evacuees + count coordinators

; counts since when the flood has started
set counter-since-flood 0
set counter 0

end
to test-something
  ; let blocked []
  ; let end-node min-one-of evacuees with [not member? self blocked] [distance one-of patches]
  ; print end-node
set geb-id-list-1 [geb-id] of patches with [geb-id >= 0 AND residents != 0] ; create a list of the geb-id of patches that contain residents
; HIER BEI REMOVE DUPLICATES GESCHIEHT DER FEHLER!
set geb-id-list-2 remove-duplicates geb-id-list-1;

end

; --------------------------------------------------------------------------------------------------------------
;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;  GO PROCEDURES   ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

to update-patches

;load flood layers
if ticks >= (prewarning-time / 10) [
    set flood-counter (ticks - (prewarning-time / 10 ))
    (ifelse
      flood-counter = 0 [
        set flood-6000 gis:load-dataset "D:/abm_data_pool/flood_dev_6000_wgs84_2.asc"
        gis:apply-raster flood-6000 water-depth
      ]
      flood-counter = 1 [
        set flood-6600 gis:load-dataset "D:/abm_data_pool/flood_dev_6600_wgs84.asc"
        gis:apply-raster flood-6600 water-depth
      ]
      flood-counter = 2 [
        set flood-7200 gis:load-dataset "D:/abm_data_pool/flood_dev_7200_wgs84.asc"
        gis:apply-raster flood-7200 water-depth
      ]
      flood-counter = 3 [
        set flood-7800 gis:load-dataset "D:/abm_data_pool/flood_dev_7800_wgs84.asc"
        gis:apply-raster flood-7800 water-depth
      ]
      flood-counter = 4 [
        set flood-8400 gis:load-dataset "D:/abm_data_pool/flood_dev_8400_wgs84.asc"
        gis:apply-raster flood-8400 water-depth
      ]
      flood-counter = 5 [
        set flood-9000 gis:load-dataset "D:/abm_data_pool/flood_dev_9000_wgs84.asc"
        gis:apply-raster flood-9000 water-depth
      ]
      flood-counter >= 6 [
        set flood-9600 gis:load-dataset "D:/abm_data_pool/flood_dev_9600_wgs84.asc"
        gis:apply-raster flood-9600 water-depth
      ]
    )
    set counter-since-flood counter-since-flood + 1
]



; update current elevation by adding the water-depth to the elevation
; ask patches [ set elevation-current elevation + water-depth ]
  ; update flooded? if water-depth is bigger than 0
  ask patches [
    if water-depth > 0 [
       set flooded? true
       ; set underground "water"
    ]
  (ifelse
      ; water-depth = -3.4 [set pcolor gray + 4]
      water-depth != -3.4 AND water-depth  > 0 AND water-depth < 0.25 AND underground = "open" [set pcolor blue + 3]
      water-depth != -3.4 AND water-depth >= 0.25 AND water-depth < 1.5 AND underground = "open" [set pcolor blue ]
      water-depth != -3.4 AND water-depth > 1.5 AND underground = "open" [set pcolor blue - 3]
   )
  ]

end

to handle-coordinators

if ticks = 0 AND counter = 0 [
    set houses-to-evacuate patches with [anchor? = true] ; set the initial list of houses to evacuate
  ]                                                      ; will only be done the first time the code is running,
  ask coordinators with [isolated? = false] [                                     ; then it will be updated (houses removed) by the following code
  ;  if last-patch-coordinator = 0 [ ; not used anymore bc other solution than working with last pathc was found
  ;    set last-patch-coordinator patch-here
  ;  ]
    ;; chosing the next house
      if next-evacuation-house = 0 OR one-of neighbors = next-evacuation-house or patch-here = next-evacuation-house OR any? patches with [geb-id = [geb-id-c] of myself] in-cone 5 90[ ; if there has no evacuation-house been set, or the coordinator is standing infront of it (which means they need a new goal)
          set next-evacuation-house min-one-of houses-to-evacuate [distance myself] ; set the next house to one of the closest houses on the list
          set geb-id-c [geb-id] of next-evacuation-house
          ask next-evacuation-house [
            set houses-to-evacuate other houses-to-evacuate ; ask the next-evacuation-house to remove itself from the list of possible houses to evacuate
        ; print "next-evacuation-house has been removed"
        ]
      ]



;; choosing the route and movement process
 if [underground] of patch-here = "fire station" [ ; coordinators leave the fire station through the same door in the 1st step
   move-to patch -223 -31
 ]

    ifelse any? patches with [underground = "building" OR underground = "dwelling-fully" OR underground = "dwelling-mainly" OR underground = "dwelling-partially" OR water-depth > 0.25] in-cone 1 80  [
    ; ifelse [underground] of patch-ahead 1 = "building" OR [underground] of patch-ahead 1 = "dwelling-fully" OR [underground] of patch-ahead 1 = "dwelling-mainly" OR [underground] of patch-ahead 1 = "dwelling-partially" OR [geb-id] of patch-ahead 1 != [geb-id-c] of self OR [water-depth] of patch-ahead 1 > 0.25 [
    ; ifelse [underground] of patch-ahead 1 = "building" OR [underground] of patch-ahead 1 = "dwelling-fully" OR [underground] of patch-ahead 1 = "dwelling-mainly" OR [underground] of patch-ahead 1 = "dwelling-partially" OR [water-depth] of patch-ahead 1 > 0.25 [
     ; ifelse [geb-id] of patch-ahead 1 != [geb-id-c] of self [
     ;   move-to patch-ahead 1
      ;]
     ; [
      ifelse patch-right-and-ahead 90 1 != nobody [
        move-to patch-right-and-ahead 90 1
        ][
        let possible-side-track-patches patches in-radius 20 with [underground = "open" OR underground = "street" OR geb-id = [geb-id-c] of myself AND water-depth < 0.25]
        move-to min-one-of possible-side-track-patches [distance [next-evacuation-house] of myself]
        ]
     ; ]
      ] [
      let possible-patches neighbors with [underground = "open" OR underground = "street" OR geb-id = [geb-id-c] of myself AND water-depth < 0.25]
      set next-patch-cor min-one-of possible-patches [distance [next-evacuation-house] of myself]

      ifelse next-patch-cor = nobody [
         move-to patch-right-and-ahead 90 1 ; with [underground = "open" OR underground = "street" OR underground = "fire station" OR geb-id = [geb-id-c] of myself AND water-depth < 0.25]
      ;  print "I'm looking for a patch that is not the closest to my goal"
      ;  set color orange
        ] [
        face next-evacuation-house
        move-to next-patch-cor
        ; set last-patch-coordinator patch-here
        ; print "the coordinator has moved to the next patch"
        ]
    ]


;; direct alarm process
    if one-of neighbors = next-evacuation-house OR patch-here = next-evacuation-house OR any? patches with [geb-id = [geb-id-c] of myself] in-cone 5 90 [ ; if C. is standing next to a building they need to warn
      ; ask evacuees-on patches with [geb-id = [geb-id] of next-evacuation-house] ; line below is a simplification, bc not every evacuee is standing on the anchor patch of the building. Needs to be adjusted!
      ; set informed-ppl informed-ppl + 1
      ask evacuees-on next-evacuation-house [                              ; ask evacuees that are in those buildings to set alarm rank +1 and update alarm-type
         ; let geb-id-evacuation-house [geb-id] of next-evacuation-house
         ;if [geb-id] of patch-here = [geb-id] of next-evacuation-house [
        set warned? true
        set alarm-rank alarm-rank + 1
     ;   print "I have been warned!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        (ifelse
            alarm-type = "" [set alarm-type "coordinators"]
            alarm-type = "sirens" [set alarm-type "sirens + coordinators" ]
            alarm-type = "word of mouth"  [set alarm-type "coordinators + word of mouth"]
            alarm-type = "sirens + word of mouth" [set alarm-type "combination"]
        )
         ]
         ; set color orange
        ; print "I, the coordinator, might have spread the coordinator alarm"
       ]

 ;; indirect alarm process
      if any? evacuees-on patch-here AND alarm-mode = "coordinators + word of mouth" OR alarm-mode = "combination" [
        ;  print "I, the coordinator, have spread the word of mouth"
          ask other evacuees in-radius 5 [
            receive-ifw
          ]
      ]
]

  while [counter = 0] [ ; makes sure that the counter is only changed once, to save calculation power
    set counter counter + 1
  ]
; print count houses-to-evacuate
end


to receive-fw
  if alarm-length >= ticks + 1 [
     set warned? true
     set alarm-rank alarm-rank + 1
      (ifelse
          alarm-type = "" [set alarm-type "sirens"]
          alarm-type = "coordinators" [set alarm-type "sirens + coordinators"]
          alarm-type = "word of mouth" [set alarm-type "sirens + word of mouth"]
          alarm-type = "coordinators + word of mouth" [set alarm-type "combination"]
      )

 ]

end

to receive-ifw
        set warned? true
        set alarm-rank alarm-rank + 1
         (ifelse
              alarm-type = "" [set alarm-type "word of mouth"]
              alarm-type = "sirens" [set alarm-type "sirens + word of mouth"]
              alarm-type = "coordinators" [set alarm-type "coordinators + word of mouth"]
              alarm-type = "sirens + coordinators" [set alarm-type "combination"]
             )
end

to decide-evacuate

; all evacuees that live outside the perimeter evacuate immediately
  ask evacuees with [evacuating? = false and alarm-rank >= 1] [
    if hh-in-perimeter? = false [
    set evacuating? true
    set color red
    ]
  ]

; flood perception
  ask evacuees with [evacuating? = false] [
    if any? patches in-radius 150 with [water-depth > 0.25 ]  [ ; and [underground] of patches in-cone 50 180 != "water" ; weiss nicht was ich mit diesem codeabschnitt gemeint habe! ; seeing 2,4 (= cell size) *50 m in an angle of 180°
      set evacuating? true
      set warned-by-flood warned-by-flood + 1
      set color red
    ]
  ]
; alarm-rank
ask evacuees with [evacuating? = false] [
  (ifelse
      alarm-rank = 1 AND ob-order = "obedient" [
        set evacuating? true
        set color red
      ]
      alarm-rank = 2 AND ob-conf = "obedient" [
        set evacuating? true
        set color red
      ]
      alarm-rank >= 3 [
        set evacuating? true
        set color red
      ]
    )
]

end



to decide-transportation
  ; if a car that the evacuee can use is within a radius of 10, set car as temporary goal
  ask evacuees with [evacuating? = true and in-car? = false] [
    ifelse car-pref = 0 AND any? cars with [car-id = [geb-id-e] of myself and stuck? = false] in-radius 20 [
        set car-pref one-of cars with [car-id = [geb-id-e] of myself and stuck? = false] in-radius 20
        set goal car-pref
     ;   print "I'm looking for a car"
    ]  [
      set goal evacuation-point
    ]
  ]

end

to find-route-foot

      set evacuation-point min-one-of exit-patches [distance myself]
      set goal evacuation-point
      face evacuation-point
end

to move-by-foot
  ; first assess the next step that you would want to make in the direction of your goal. If the in front of the evacuee (in speed distance)
  ; is clear, move fd speed
  ; if building ahead, move around/along building
  ; if flood ahead, move in other direction
;ask evacuees [
 ; ask evacuees with [evacuating? = true and in-car? = false and  any? (neighbors with [underground = "open" OR underground = "street" OR geb-id = [geb-id-e] of myself])][ ; neighbors thing is a quick fix, needs to be fixed later
    ; might be possible to calculate the available patches as a to report procedure, so that the code is clearer and actually works
    ifelse one-of neighbors = evacuation-point [
    move-to evacuation-point
    ][
    ifelse any? patches with [underground = "building" OR underground = "dwelling-fully" OR underground = "dwelling-mainly" OR underground = "dwelling-partially" OR water-depth > 0.25 AND geb-id != [geb-id-e] of myself] in-cone 1 80  [
      move-to patch-right-and-ahead 90 1
      ][
     let possible-patches neighbors with [underground = "open" OR underground = "street" OR geb-id = [geb-id-e] of myself AND water-depth < 0.25]
     let next-patch-e min-one-of possible-patches [distance [goal] of myself]
     ifelse next-patch-e = nobody [
      set isolated? true
      set isolated isolated + 1
     ; print "I'm isolated"
     ][
     face goal
     move-to next-patch-e
     ]
    ]
    ]

end

to pick-up-evacuee

  ask cars with [stuck? = false] [
   ( ifelse
      any? evacuees-here with [household = [car-id] of myself] AND [evacuees-no] of self = 0 [ ;the first evacuee in a car has to be the owner
     ;  create-link-to one-of evacuees-here with [household = [car-id] of myself] [tie]
      ask one-of evacuees-here with [household = [car-id] of myself] [die]
      set evacuees-no evacuees-no + 1
      ; set color yellow
    ;  print " I have picked up my owner"
      ; if [in-panic?] of my-links = true [
      ;    set evacuee-panicking-in-car? true
      ]

    any? evacuees-here and evacuees-no > 0  and evacuee-panicking-in-car? = false ; the other evacuees can be strangers
    [
      repeat count (evacuees-here) [
      if evacuees-no < seats [
      ;  create-link-to one-of evacuees-here [tie]
        ask one-of evacuees-here [die]
        set evacuees-no evacuees-no + 1
        set evacuated-by-car evacuated-by-car + 1
     ;  print " I have picked up an extra evacuee"
      ]
     ]
    ] )
    ]



end

to find-route-car

ask cars with [evacuees-no > 0 AND evacuated? = false AND stuck? = false ] [
    ifelse evacuation-point = 0 [
      set evacuation-point min-one-of street-next-to-exit [distance myself]
      face evacuation-point
     ; print "I have a destination now"
    ][
    ; else calculate a new closest point. if this point is closer, transform the possible ep into the new ep
     let possible-evacuation-point min-one-of street-next-to-exit [distance myself]
     if distance evacuation-point > distance possible-evacuation-point [
       set evacuation-point possible-evacuation-point
       face evacuation-point
     ; print "I have been redirected"
     ]
    ]
 ]

end

to move-by-car

ask cars with [evacuees-no > 0 and evacuated? = false and stuck? = false] [
     ; repeat 1 [
    if last-patch-car = 0 [
      set last-patch-car patch-here
    ]
      set choices neighbors with [underground = "street" AND water-depth < 0.3]
      ; ask last-patch-car [set choices other choices]
      if choices = nobody [
        set stuck? true
      ; print "I am stuck!"
        set stuck stuck + 1 die
      ]

     set next-patch min-one-of choices [distance [evacuation-point] of myself]
     if last-patch-car = next-patch [
  ;    print " I entered the last-patch-car = next-patch loop"
      ; loop to avoid that they move back to the patch that they came from
      while [ last-patch-car = next-patch ] [
        set next-patch min-one-of choices [distance [evacuation-point] of myself]
        ]
      ]
      ifelse next-patch = nobody [
      set stuck? true
      ; print "I am stuck!"
      set stuck stuck + 1 die
      ][
        face next-patch
        move-to next-patch
     ;   print "The car has moved to the next patch"
    ]


     ]

end
to dying
  ; check if evacuees reached end goal. If so, set evacuated true and hide
  ask evacuees [
    if evacuating? = true and [exit?] of patch-here = true [ set evacuated evacuated + 1 die ]
  ]
  ask coordinators [
    if [exit?] of patch-here = true [ set evacuated evacuated + 1 die ]
  ]
  ask cars [
    if [water-depth] of patch-here >= 0.3 [
      set stuck? true
      ; print "I am stuck!"
      set stuck stuck + 1 die
   ]
    if evacuation-point = patch-here or patch-here = street-next-to-exit? = true [
       ;  print "I was evacuated through a car!"
        set evacuated evacuated + evacuees-no
        die
    ]
  ]




  ; kann ev. noch in ein to-report procedure umgewandelt werden, damit der code nicht repetiert werden muss
ask evacuees [
    if [underground] of patch-here = "open" OR [underground] of patch-here = "street" AND [water-depth] of patch-here >= 0.25  [set causalities causalities + 1 die ]
    if [underground] of patch-here = "building" AND [water-depth] of patch-here >= 1.5  [ set causalities causalities + 1 die ]

    if [underground] of neighbors = "open" AND [water-depth] of neighbors >= 0.25 [ set isolated isolated + 1 ]
    if [underground] of neighbors = "building" AND [water-depth] of neighbors >= 1.5  [ set isolated isolated + 1 ]
]

ask coordinators [
    if [underground] of patch-here = "open" OR [underground] of patch-here = "street"AND [water-depth] of patch-here >= 0.25  [set causalities causalities + 1 die ]
    if [underground] of patch-here = "building" AND [water-depth] of patch-here >= 1.5  [ set causalities causalities + 1 die ]

    if [underground] of neighbors = "open" AND [water-depth] of neighbors >= 0.25 [ set isolated isolated + 1 ]
    if [underground] of neighbors = "building" AND [water-depth] of neighbors >= 1.5  [ set isolated isolated + 1 ]
  ]

end

to test-it ;; to test functions outside of normal environment
  ask patch 79 -98 [
    sprout-cars 1 [ set seats 5 set evacuees-no 0 set size 5]
    sprout-evacuees 6 [set size 5]
  ]
  ask cars-on patch 79 -98 [
    repeat count (evacuees-here) [
      if evacuees-no < seats [
         create-link-to one-of evacuees-here
         set evacuees-no evacuees-no + 1
      ]
    ]
  ]
  ask evacuees-on patch 79 -98 [fd random 20 ]

end
@#$#@#$#@
GRAPHICS-WINDOW
532
136
1133
548
-1
-1
1.0
1
10
1
1
1
0
0
0
1
-296
296
-201
201
0
0
1
ticks
30.0

SLIDER
547
766
719
799
number-of-evacuees
number-of-evacuees
0
2000
0.0
1
1
NIL
HORIZONTAL

BUTTON
535
85
598
118
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
540
569
843
599
TESTING AND DEBUGGING
13
105.0
0

TEXTBOX
550
809
700
835
no. of residents in \ndevelopment perimeter: 606
10
0.0
1

BUTTON
743
727
879
760
NIL
setup-coordinators
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
902
678
992
711
NIL
setup-cars
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
900
727
1011
760
NIL
setup-patches\n
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
22
324
203
357
number-of-coordinators
number-of-coordinators
0
100
20.0
1
1
NIL
HORIZONTAL

BUTTON
777
85
851
118
NIL
clear-all
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
743
678
861
711
setup-elevation
setup-elevation
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
548
677
720
710
number-of-cars
number-of-cars
0
700
0.0
1
1
NIL
HORIZONTAL

TEXTBOX
555
718
747
746
( current setup: no. of cars per household: 1.38)
10
0.0
1

BUTTON
901
773
966
806
NIL
test-it
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
26
178
198
211
obedience-order
obedience-order
0
1
0.6
0.1
1
NIL
HORIZONTAL

SLIDER
23
269
202
302
obedience-confirmation
obedience-confirmation
0
1
0.8
0.1
1
NIL
HORIZONTAL

TEXTBOX
20
151
252
179
percentage of people that evacuate after first alarm:
10
0.0
1

TEXTBOX
21
225
267
251
percentage of people (that haven't evacuated in the first run) that evacuate after second alarm:
10
0.0
1

SLIDER
25
100
210
133
ratio-residents-externals
ratio-residents-externals
0
1
0.8
0.1
1
NIL
HORIZONTAL

TEXTBOX
30
79
180
97
ratio of residents to externals:
10
0.0
1

CHOOSER
894
601
1071
646
background-display
background-display
"vectordata" "rasterdata" "rasterdata +elevation"
1

BUTTON
701
85
764
118
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
610
85
687
118
go-once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
276
171
448
204
prewarning-time
prewarning-time
0
480
0.0
10
1
min
HORIZONTAL

SLIDER
275
267
447
300
receive-alarm
receive-alarm
0
1
0.9
0.1
1
NIL
HORIZONTAL

TEXTBOX
275
149
475
184
the alarm starts X minutes before the flood: 
10
0.0
1

TEXTBOX
285
232
459
266
percentage of people that receive the warning:
10
0.0
1

TEXTBOX
287
317
437
345
how many time minutes the alarm gets repeated:
10
0.0
1

SLIDER
274
358
446
391
alarm-length
alarm-length
0
100
12.0
1
1
NIL
HORIZONTAL

CHOOSER
261
86
476
131
ALARM-MODE
ALARM-MODE
"none" "sirens" "coordinators" "sirens + coordinators" "sirens + word of mouth" "coordinators + word of mouth" "combination"
5

TEXTBOX
298
54
462
72
ALARM SCENARIOS
13
105.0
1

BUTTON
743
775
857
808
NIL
test-something\n
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
69
55
219
73
AGENTS
13
105.0
1

TEXTBOX
540
53
707
87
RUNNING THE MODEL 
13
105.0
1

CHOOSER
549
602
687
647
size-of-patches
size-of-patches
1 2
0

SWITCH
706
604
861
637
debugging-setup
debugging-setup
1
1
-1000

TEXTBOX
1172
43
1322
61
MODEL OBSERVATION
13
105.0
1

MONITOR
1172
73
1268
118
isolated people
isolated
17
1
11

PLOT
1172
136
1372
286
evacuated
time
people
0.0
0.0
0.0
0.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot evacuated"

PLOT
1176
476
1376
626
alarm-type
time
evacuees
0.0
500.0
0.0
500.0
true
false
"" ""
PENS
"default" 1.0 0 -955883 true "" "plot count evacuees with [alarm-type = \"word of mouth\"]"
"pen-1" 1.0 0 -7500403 true "" "plot count evacuees with [alarm-type = \"sirens\"]"
"pen-2" 1.0 0 -2674135 true "" "plot count evacuees with [alarm-type = \"coordinators\"]"
"pen-3" 1.0 0 -6459832 true "" "plot count evacuees with [alarm-type = \"combination\"]"
"pen-4" 1.0 0 -1184463 true "" "plot count evacuees with [alarm-type = \"sirens + coordinators\"]"
"pen-5" 1.0 0 -10899396 true "" "plot count evacuees with [alarm-type = \"sirens + word of mouth\"]"
"pen-6" 1.0 0 -13840069 true "" "plot count evacuees with [alarm-type = \"coordinators + word of mouth\"]"

PLOT
1174
301
1374
451
causalities
time
people
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot causalities"

MONITOR
1285
73
1354
118
stuck cars
stuck
17
1
11

CHOOSER
1177
650
1315
695
mode
mode
"day" "night"
1

TEXTBOX
345
215
392
233
SIRENS
11
105.0
1

TEXTBOX
311
410
461
428
WORD OF MOUTH
11
105.0
1

SLIDER
264
437
457
470
word-of-mouth-spreaders
word-of-mouth-spreaders
0
1
0.9
0.1
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;combination&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="395"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="causalities2" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="20"/>
    <metric>causalities</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;none&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="395"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="prewarning time" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>causalities</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;combination&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="395"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="299"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="0"/>
      <value value="10"/>
      <value value="20"/>
      <value value="30"/>
      <value value="40"/>
      <value value="50"/>
      <value value="60"/>
      <value value="70"/>
      <value value="80"/>
      <value value="90"/>
      <value value="100"/>
      <value value="110"/>
      <value value="120"/>
      <value value="130"/>
      <value value="140"/>
      <value value="150"/>
      <value value="160"/>
      <value value="170"/>
      <value value="180"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="11"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="warning-type-check" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="50"/>
    <metric>count evacuees with [warning-type = "sirens"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;combination&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="395"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="299"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="11"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="220"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="causalities-combination" repetitions="10" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="15"/>
    <metric>causalities</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;combination&quot;"/>
      <value value="&quot;none&quot;"/>
      <value value="&quot;sirens&quot;"/>
      <value value="&quot;coordinators&quot;"/>
      <value value="&quot;word of mouth&quot;"/>
      <value value="&quot;sirens + coordinators&quot;"/>
      <value value="&quot;sirens + word of mouth&quot;"/>
      <value value="&quot;coordinators word of mouth&quot;"/>
      <value value="&quot;combination&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="395"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="0"/>
      <value value="10"/>
      <value value="20"/>
      <value value="30"/>
      <value value="40"/>
      <value value="50"/>
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Sirenen" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated (sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>count evacuees with [warning-type = "sirens"]</metric>
    <metric>count evacuees with [warning-type = "sirens + coordinators"]</metric>
    <metric>count evacuees with [warning-type = "sirens + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "combination"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;none&quot;"/>
      <value value="&quot;sirens&quot;"/>
      <value value="&quot;sirens + coordinators&quot;"/>
      <value value="&quot;sirens + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="receive-warning" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="warning-length" first="0" step="1" last="12"/>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Coordinators" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>count evacuees with [warning-type = "coordinators"]</metric>
    <metric>count evacuees with [warning-type = "sirens + coordinators"]</metric>
    <metric>count evacuees with [warning-type = "coordinators + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "combination"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;none&quot;"/>
      <value value="&quot;coordinators&quot;"/>
      <value value="&quot;sirens + coordinators&quot;"/>
      <value value="&quot;coordinators + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-coordinators" first="0" step="5" last="50"/>
    <enumeratedValueSet variable="size-of-patches">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Word of Mouth" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>count evacuees with [warning-type = "word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "sirens + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "coordinators + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "combination"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;none&quot;"/>
      <value value="&quot;word of mouth&quot;"/>
      <value value="&quot;sirens + word of mouth&quot;"/>
      <value value="&quot;coordinators + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="word-of-mouth-spreaders" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Vorwarnzeit" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>sum [evacuees-no] of cars (wie viele in cars unterwegs sind)</metric>
    <metric>evacuated-by-car</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;none&quot;"/>
      <value value="&quot;sirens&quot;"/>
      <value value="&quot;coordinators&quot;"/>
      <value value="&quot;word of mouth&quot;"/>
      <value value="&quot;sirens + word of mouth&quot;"/>
      <value value="&quot;sirens + coordinators&quot;"/>
      <value value="&quot;coordinators + word of mouth&quot;"/>
      <value value="&quot;combination&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="prewarning-time" first="0" step="10" last="120"/>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Reaktionsbereitschaft" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>warned-by-flood</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <steppedValueSet variable="obedience-order" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="obedience-confirmation" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;combination&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Vorwarnzeit_adapted_wom" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>sum [evacuees-no] of cars</metric>
    <metric>evacuated-by-car</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="prewarning-time" first="60" step="10" last="120"/>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>count turtles</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="120"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Vorwarnzeit_adapted1" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>sum [evacuees-no] of cars</metric>
    <metric>evacuated-by-car</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;sirens + word of mouth&quot;"/>
      <value value="&quot;sirens + coordinators&quot;"/>
      <value value="&quot;coordinators + word of mouth&quot;"/>
      <value value="&quot;combination&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="prewarning-time" first="0" step="10" last="40"/>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Sirenen3" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>((sum [warning-rank] of evacuees) / (count evacuees with [warned? = true]))</metric>
    <metric>count evacuees with [warning-type = "sirens"]</metric>
    <metric>count evacuees with [warning-type = "coordinators"]</metric>
    <metric>count evacuees with [warning-type = "word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "sirens + coordinators"]</metric>
    <metric>count evacuees with [warning-type = "sirens + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "combination"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;none&quot;"/>
      <value value="&quot;sirens&quot;"/>
      <value value="&quot;sirens + coordinators&quot;"/>
      <value value="&quot;sirens + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="receive-warning" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="warning-length" first="9" step="1" last="12"/>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Sirenen2" repetitions="5" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>((sum [warning-rank] of evacuees) / (count evacuees with [warned? = true]))</metric>
    <metric>count evacuees with [warning-type = "sirens"]</metric>
    <metric>count evacuees with [warning-type = "coordinators"]</metric>
    <metric>count evacuees with [warning-type = "word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "sirens + coordinators"]</metric>
    <metric>count evacuees with [warning-type = "sirens + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "combination"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;none&quot;"/>
      <value value="&quot;sirens&quot;"/>
      <value value="&quot;sirens + coordinators&quot;"/>
      <value value="&quot;sirens + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="receive-warning" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="warning-length" first="5" step="1" last="8"/>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Reaktionsbereitschaft_1x" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>warned-by-flood</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <steppedValueSet variable="obedience-order" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="obedience-confirmation" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;combination&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Coordinators_wom_only" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>count evacuees with [warning-type = "coordinators"]</metric>
    <metric>count evacuees with [warning-type = "sirens + coordinators"]</metric>
    <metric>count evacuees with [warning-type = "coordinators + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "combination"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;coordinators + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-coordinators" first="0" step="5" last="50"/>
    <enumeratedValueSet variable="size-of-patches">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Word of Mouth_coord_only" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>count evacuees with [warning-type = "word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "sirens + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "coordinators + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "combination"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;coordinators + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="word-of-mouth-spreaders" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Sirenen" repetitions="20" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated (sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>count evacuees with [warning-type = "sirens"]</metric>
    <metric>count evacuees with [warning-type = "sirens + coordinators"]</metric>
    <metric>count evacuees with [warning-type = "sirens + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "combination"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;none&quot;"/>
      <value value="&quot;sirens&quot;"/>
      <value value="&quot;sirens + coordinators&quot;"/>
      <value value="&quot;sirens + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="receive-warning" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="warning-length" first="0" step="1" last="12"/>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Vorwarnzeit" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>sum [evacuees-no] of cars (wie viele in cars unterwegs sind)</metric>
    <metric>evacuated-by-car</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;coordinators + word of mouth&quot;"/>
      <value value="&quot;combination&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="prewarning-time" first="0" step="10" last="120"/>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Coordinators_wom" repetitions="3" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>count evacuees with [warning-type = "coordinators"]</metric>
    <metric>count evacuees with [warning-type = "sirens + coordinators"]</metric>
    <metric>count evacuees with [warning-type = "coordinators + word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "combination"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;coordinators + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-coordinators" first="0" step="5" last="50"/>
    <enumeratedValueSet variable="size-of-patches">
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Vorwarnzeit_wom" repetitions="2" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>sum [evacuees-no] of cars</metric>
    <metric>evacuated-by-car</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;coordinators + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="word-of-mouth-spreaders">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <steppedValueSet variable="prewarning-time" first="0" step="10" last="120"/>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Word of Mouth_coord_adapted" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <metric>count evacuees with [warning-type = "word of mouth"]</metric>
    <metric>count evacuees with [warning-type = "coordinators + word of mouth"]</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;coordinators + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="word-of-mouth-spreaders" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Word of Mouth_20min" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="12"/>
    <metric>causalities</metric>
    <metric>isolated</metric>
    <metric>evacuated</metric>
    <metric>(sum [warning-rank] of evacuees) / (count evacuees with [warned? = true])</metric>
    <enumeratedValueSet variable="obedience-order">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="evacuees-in-panic">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="obedience-confirmation">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ratio-residents-externals">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-mode">
      <value value="&quot;none&quot;"/>
      <value value="&quot;sirens + word of mouth&quot;"/>
      <value value="&quot;coordinators + word of mouth&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-evacuees">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="receive-warning">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-coordinators">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="size-of-patches">
      <value value="1"/>
    </enumeratedValueSet>
    <steppedValueSet variable="word-of-mouth-spreaders" first="0" step="0.1" last="1"/>
    <enumeratedValueSet variable="debugging-setup">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mode">
      <value value="&quot;night&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-cars">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="prewarning-time">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="background-display">
      <value value="&quot;rasterdata&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="warning-length">
      <value value="12"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
