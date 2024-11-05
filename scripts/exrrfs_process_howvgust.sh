#!/bin/bash

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. ${GLOBAL_VAR_DEFNS_FP}
. $USHdir/source_util_funcs.sh
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; set -u -x; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( readlink -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# Print message indicating entry into script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that runs the preprocess of retrieving
the firstguess of ocean signifcant wave height (HOWV) and 10-m wind-gust
 (GUST)field from WW3 forecasts with FV3 for the specified cycle.
========================================================================"
#
#-----------------------------------------------------------------------
#
# Specify the set of valid argument names for this script/function.  
# Then process the arguments provided to this script/function (which 
# should consist of a set of name-value pairs of the form arg1="value1",
# etc).
#
#-----------------------------------------------------------------------
#
valid_args=( "CYCLE_DIR" )
process_args valid_args "$@"
#
#-----------------------------------------------------------------------
#
# For debugging purposes, print out values of arguments passed to this
# script.  Note that these will be printed out only if VERBOSE is set to
# TRUE.
#
#-----------------------------------------------------------------------
#
print_input_args valid_args
#
#-----------------------------------------------------------------------
#
# Set environment
#
#-----------------------------------------------------------------------
#
ulimit -s unlimited
ulimit -a

case $MACHINE in
#
"WCOSS2")
  APRUN="mpiexec -n 1 -ppn 1"
  ;;
#
"HERA")
  APRUN="srun --export=ALL"
  ;;
#
"JET")
  APRUN="srun --export=ALL"
  ;;
#
"ORION")
  APRUN="srun --export=ALL"
  ;;
#
"HERCULES")
  APRUN="srun --export=ALL"
  ;;
#
esac
#
#-----------------------------------------------------------------------
#
# Define some tools
#
#-----------------------------------------------------------------------
export WGRIB2=${WGRIB2:-wgrib2}
print_info_msg "$VERBOSE" "WGRIB2 is ${WGRIB2}"
#
#
#-----------------------------------------------------------------------
#
# Extract from CDATE the starting year, month, day, and hour of the
# forecast.  These are needed below for various operations.
#
#-----------------------------------------------------------------------
#
START_DATE=$(echo "${CDATE}" | sed 's/\([[:digit:]]\{2\}\)$/ \1/')
YYYYMMDDHH=$(date +%Y%m%d%H -d "${START_DATE}")
JJJ=$(date +%j -d "${START_DATE}")

YYYY=${YYYYMMDDHH:0:4}
MM=${YYYYMMDDHH:4:2}
DD=${YYYYMMDDHH:6:2}
HH=${YYYYMMDDHH:8:2}
YYYYMMDD=${YYYYMMDDHH:0:8}

YYJJJHH=$(date +"%y%j%H" -d "${START_DATE}")
PREYYJJJHH=$(date +"%y%j%H" -d "${START_DATE} 1 hours ago")

CDATEymdh=${YYYYMMDDHH}

FCST_DATE=$(date +"%Y%m%d%H" -d "${START_DATE} 1 hours ago")
PRE_YYYYMMDDHH=$(date +"%Y%m%d%H" -d "${START_DATE} 1 hour ago")
PRE_YYYYMMDD=$(echo ${PRE_YYYYMMDDHH} | cut -c1-8)
PRE_HH=$(echo ${PRE_YYYYMMDDHH} | cut -c9-10)

#
#-----------------------------------------------------------------------
#
# Grid Specification for domain of 3DRTMA (used by wgrib2)
#
#-----------------------------------------------------------------------
#
#grid_specs_WG2wexp: for operational RTMA/URMA
grid_specs_WG2wexp="lambert:265.0:25.0:25.0 233.723448:2345:2539.703 19.228976:1597:2539.703"

#grid_specs_hrrr: for exp hrrr-based 3D RTMA on CONUS domain
grid_specs_hrrr="lambert:-97.5:38.5:38.5 -122.719528:1799:3000.0 21.138123:1059:3000.0"

#grid_specs_rrfsnarll: for exp RRFS-based 3D RTMA on North America domain on Rotated Latlon grid
grid_specs_rrfsnarll="rot-ll:247.0:-35.0:0.0 299.0:4881:0.025 -37.0:2961:0.025"

#grid_specs_rrfsnapol: for exp RRFS-based 3D RTMA on North America domain on Polar Stereographic grid
grid_specs_rrfsnapol="nps:245.0:60.0 206.5:5200:3170.0 -4.0:3268:3170.0"

grid_specs=${grid_specs_rrfsnarll}
#
#-----------------------------------------------------------------------
#
# Define fix dir (for slmask.grb2 file)
#
#-----------------------------------------------------------------------
#
# FIXurma=$FIX_GSI/${PREDEF_GRID_NAME}
# print_info_msg "$VERBOSE" "FIXurma is $FIXurma"
#
#
#-----------------------------------------------------------------------
#
# Look for the WW3-firstguess for ocean significant wave height (HOWV)
#
#-----------------------------------------------------------------------
#
#
#  Mask for the correct interpolation of the howv Background.
# ???? ----> need to find slmask.grb2 for NA-3km RLL grid
#       cp $FIXurma/${RUN}_slmask_nolakes.grb2 slmask.grb2
#
# Wave Background at Great Lakes
  print_info_msg "$VERBOSE" "COMINww3GL is $COMINww3GL (Wave background from Great Lakes model)"

   found_ww3gesGL=no
   ic=0
   while [ $ic -le 23 ] ; do
      ww3FHH_GL=$ic
      ww3FHH_GL=`printf %03d $ww3FHH_GL`
      ww3CYCLE_GL=`$NDATE -$ww3FHH_GL $CDATEymdh`
      ww3PDY_GL=`echo $ww3CYCLE_GL |cut -c1-8`
      ww3CC_GL=`echo $ww3CYCLE_GL |cut -c9-10`
#
      probe_ww3_GL_guess_grb2=$COMINww3GL/glwu.${ww3PDY_GL}/glwu.grlr_500m.t${ww3CC_GL}z.grib2
#
      if [ -s $probe_ww3_GL_guess_grb2 ]; then

         print_info_msg "$VERBOSE" "found wave background for Great Lakes: $probe_ww3_GL_guess_grb2"
         cpreq $probe_ww3_GL_guess_grb2 ww3.guess5.grb2
#        cp -p $probe_ww3_GL_guess_grb2 ww3.guess5.grb2
         cp -p $probe_ww3_GL_guess_grb2 $COMOUT/glwu.grlr_500m.t${ww3CC_GL}z.grib2     # save for retro run
         if [ $ic == 0 ]; then
            FHH_st="(HTSGW:surface:anl)"
         else
            FHH_st="(HTSGW:surface:$ic hour fcst)"
         fi
         $WGRIB2 ww3.guess5.grb2 -match "${FHH_st}" -grib ww3GL.guess.grb2

         GL_InputGribmerge=' -i ww3GL.guess.grb2 '

#        echo "export ww3CYCLE_GL=$ww3CYCLE_GL" >> $COMOUT/urma2p5.t${cyc}z.envir.sh
#        echo "export ww3FHH_GL=$ww3FHH_GL" >> $COMOUT/urma2p5.t${cyc}z.envir.sh

         found_ww3gesGL=yes

         break
      else
         let "ic=ic+1"
      fi
   done
   if [[ ${found_ww3gesGL} = no ]] ; then
       err_exit "No WW3 guess for Great Lakes available. The missing files in the above while-do loop are of the from $COMINww3GL/glwu.${ww3PDY}/glwu.grlr_500m.t${ww3CC}z.grib2. The script must be able to find at least one file out of the 24 files that it queries"
   fi
#
# Ocean Waves Background
  print_info_msg "$VERBOSE" "COMINww3 is $COMINww3 (Wave background from WW3 Ocean Wave model)"
   found_ww3ges=no
   ic=0
   while [ $ic -le 24 ] ; do
      ww3FHH=$ic
      ww3FHH=`printf %03d $ww3FHH`
      ww3CYCLE=`$NDATE -$ww3FHH $CDATEymdh`
      ww3PDY=`echo $ww3CYCLE |cut -c1-8`
      ww3CC=`echo $ww3CYCLE |cut -c9-10`

#     "set -A" only works for K-Shell 
#     set -A  probe_ww3_guess_grb2  "$COMINww3/gfs.${ww3PDY}/${ww3CC}/wave/gridded/gfswave.t${ww3CC}z.arctic.9km.f${ww3FHH}.grib2" \
#                                   "$COMINww3/gfs.${ww3PDY}/${ww3CC}/wave/gridded/gfswave.t${ww3CC}z.global.0p16.f${ww3FHH}.grib2"
#     In Bash, to create an array:
      declare -a  probe_ww3_guess_grb2=( \
          [0]="$COMINww3/gfs.${ww3PDY}/${ww3CC}/wave/gridded/gfswave.t${ww3CC}z.arctic.9km.f${ww3FHH}.grib2"  \
          [1]="$COMINww3/gfs.${ww3PDY}/${ww3CC}/wave/gridded/gfswave.t${ww3CC}z.global.0p16.f${ww3FHH}.grib2" \
      )
#     or the following way to create 
#       probe_ww3_guess_grb2=("$COMINww3/gfs.${ww3PDY}/${ww3CC}/wave/gridded/gfswave.t${ww3CC}z.arctic.9km.f${ww3FHH}.grib2"   \
#                             "$COMINww3/gfs.${ww3PDY}/${ww3CC}/wave/gridded/gfswave.t${ww3CC}z.global.0p16.f${ww3FHH}.grib2"   )

      if [ -s "${probe_ww3_guess_grb2[0]}" ] && \
         [ -s "${probe_ww3_guess_grb2[1]}" ]    ; then

         print_info_msg "$VERBOSE" "found wave background for Arctic: ${probe_ww3_guess_grb2[0]}"
         print_info_msg "$VERBOSE" "found wave background for Global: ${probe_ww3_guess_grb2[1]}"
         cpreq ${probe_ww3_guess_grb2[0]} ww3.guess0.grb2
#        cp -p ${probe_ww3_guess_grb2[0]} ww3.guess0.grb2
         cpreq ${probe_ww3_guess_grb2[1]} ww3.guess1.grb2
#        cp -p ${probe_ww3_guess_grb2[1]} ww3.guess1.grb2

         cp -p ${probe_ww3_guess_grb2[0]} $COMOUT/gfswave.t${ww3CC}z.arctic.9km.f${ww3FHH}.grib2     # save for retro run
         cp -p ${probe_ww3_guess_grb2[1]} $COMOUT/gfswave.t${ww3CC}z.global.0p16.f${ww3FHH}.grib2     # save for retro run

         ${HOMEscript}/exrrfs_GribMerge_urma.sh ${GL_InputGribmerge} -i ww3.guess0.grb2 -i ww3.guess1.grb2 \
                        -v HTSGW -g "${grid_specs}" \
                        -m slmask.grb2 \
                        -o ww3.guess.grb2
 
#        echo "export ww3CYCLE=$ww3CYCLE" >> $COMOUT/${RUN}.t${cyc}z.envir.sh
#        echo "export ww3FHH=$ww3FHH" >> $COMOUT/${RUN}.t${cyc}z.envir.sh
         found_ww3ges=yes
         break
      else
         let "ic=ic+1"
      fi
   done
   if [[ ${found_ww3ges} = no ]] ; then
       err_exit "No ocean WW3 guess available. Check availability of  \
gfs.${ww3PDY}/${ww3CC}/wave/gridded/gfswave.t${ww3CC}z.arctic.9km.f${ww3FHH}.grib2, \
gfs.${ww3PDY}/${ww3CC}/wave/gridded/gfswave.t${ww3CC}z.global.0p16.f${ww3FHH}.grib2 \
queried in the above while-do-loop."
   fi

   cp -p ww3.guess.grb2 $COMOUT/rrfs.t${HH}z.ww3.guess.3drtma.grb2
#
#-----------------------------------------------------------------------
#
# looking for firstguess of Wind Gust (from 1-h forecast grib2 file of RRFS)
#
#-----------------------------------------------------------------------
#
   rrfs_f01_grb2=${RRFS_PRODROOT}/rrfs.${PRE_YYYYMMDD}/${PRE_HH}/rrfs.t${PRE_HH}z.prslev.f001.grib2
   if [[ -f ${rrfs_f01_grb2} ]] ; then 
      print_info_msg "VERBOSE" "found RRFS 1-hour forecast grib2 file ${rrfs_f01_grb2} and retrieve 10-m Wind Gust from it: "
      ln -sf ${rrfs_f01_grb2}   ./rrfs_f001.grib2
      wgrib2 ./rrfs_f001.grib2 | grep "GUST" | wgrib2 -i ./rrfs_f001.grib2 -grib ./rrfs_t${PRE_HH}z.gust.sfc.f001.grib2
      # wgrib2 ./rrfs_f001.grib2 -match ":GUST:" -grib ./rrfs_t${PRE_HH}z.gust.sfc.f001.grib2
      export err=$?; err_chk
      cp -p ./rrfs_t${PRE_HH}z.gust.sfc.f001.grib2 $COMOUT/rrfs_t${PRE_HH}z.gust.sfc.f001.grib2
   else
      err_exit "Could NOT find RRFS 1-hour forecast grib2 file ${rrfs_f01_grb2}, exit with error.  "
   fi

###################################################################################
#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Retrieving WW3 GUESS for HOWV AND RRFS GUESS for GUST PROCESS completed successfully!!!

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/function.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1

