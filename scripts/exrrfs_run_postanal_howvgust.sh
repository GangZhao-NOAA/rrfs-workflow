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

This is the ex-script for the task that runs a analysis with FV3 for the
specified cycle.
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
valid_args=( "cycle_dir" "gsi_type" "ob_type" "mem_type" \
             "slash_ensmem_subdir" "fg_root" \
             "analworkdir" )
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

  "WCOSS2")
    ncores=$(( NNODES_RUN_PREPSTART*PPN_RUN_PREPSTART))
    APRUN="mpiexec -n ${ncores} -ppn ${PPN_RUN_PREPSTART}"
    ;;

  "HERA")
    APRUN="srun --export=ALL --mem=0"
    ;;

  "ORION")
    ulimit -s unlimited
    ulimit -a
    APRUN="srun --export=ALL"
    ;;

  "HERCULES")
    ulimit -s unlimited
    ulimit -a
    APRUN="srun --export=ALL"
    ;;

  "JET")
    APRUN="srun --export=ALL --mem=0"
    ;;

  *)
    err_exit "\
Run command has not been specified for this machine:
  MACHINE = \"$MACHINE\"
  APRUN = \"$APRUN\""
    ;;

esac

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

adate=${YYYYMMDDHH}
#
#-----------------------------------------------------------------------
#
# Define fix and background path
#
#-----------------------------------------------------------------------
#
fixgriddir=$FIX_GSI/${PREDEF_GRID_NAME}
if [ "${CYCLE_TYPE}" = "spinup" ]; then
  if [ "${mem_type}" = "MEAN" ]; then
    bkpath=${cycle_dir}/ensmean/fcst_fv3lam_spinup/INPUT
  else
    bkpath=${cycle_dir}${slash_ensmem_subdir}/fcst_fv3lam_spinup/INPUT
  fi
else
  if [ "${mem_type}" = "MEAN" ]; then
    bkpath=${cycle_dir}/ensmean/fcst_fv3lam/INPUT
  else
    bkpath=${cycle_dir}${slash_ensmem_subdir}/fcst_fv3lam/INPUT
  fi
fi
# decide background type
if [ -r "${bkpath}/coupler.res" ]; then
  BKTYPE=0              # warm start
else
  BKTYPE=1              # cold start
fi

#
#-----------------------------------------------------------------------
#
# Regridding the firstguess of ocean Significant Wave Height (howv) field 
# (in analysis of surface file) 3DRTMA
# regridding the data from the Extended Schmidt Gnomonic (ESG) grid to 
# the Rotated Latlon (RLL) grid
#
#-----------------------------------------------------------------------
#
if [[ "${NET}" == "RTMA"* ]] && [[ "${MACHINE,,}" == "wcoss2" ]] && [[ "${BKTYPE}" -eq 0 ]] && \
   [[ "${DO_HOWV^^}" == "TRUE" ]] ; then

  # linking the fv3-lam grid specification file (fixed file for RRFS_NA_3km_c3463)
   rm -f ./fv3_grid_spec_esg.nc
  #ln -sf ${FIX_GSI}/RRFS_NA_3km/fv3_grid_spec            ./fv3_grid_spec_esg.nc
   ln -sf ${FIX_GSI}/${PREDEF_GRID_NAME}/fv3_grid_spec            ./fv3_grid_spec_esg.nc

  # linking the analysis file of surface fields (netcdf format), 
  # including the 2-D fields (HOWV and Wind Gust) on ESG grid
  # which would be regridded from ESG grid to RLL grid
  #ln -sf ./fv3_sfcdata                                   ./input_data_esg.nc
   ln -sf ${bkpath}/sfc_data.nc                           ./input_data_esg.nc
   
  # regrdding significant wave height (howv) from RLL grid to ESG grid
   export varname="howv"
   export varname_grb="HTSGW"
  # For incremental inter4polation, linking the firstguess file
  # of surface fields (netcdf format), including HOWV and GUST
   if [ -f ${bkpath}/sfc_data_esg_fgs_${varname}.nc ] ; then
      print_info_msg "VERBOSE" "using incremental interpolation in regridding ${varname} from ESG to RLL"
      flag_increment_intrp=".true."
      ln -sf ${bkpath}/sfc_data_esg_fgs_${varname}.nc                  ./input_data_esg_fgs.nc
   else
      print_info_msg "VERBOSE" "using full variable interpolation in regridding ${varname} from ESG to RLL"
      flag_increment_intrp=".false."
   fi

  # output_data_rll.nc      --> netcdf file which stores the "new(e.g., analysis)" field on RLL grid
   rm -f ./output_data_rll.nc
   ln -sf ./sfc_data_rll_anl_${varname}.nc   ./output_data_rll.nc

  # set up the namelist for regrdding
   rm -f ./esg2rll_namelist
cat << EOF > ./esg2rll_namelist
 &SETUP
   varname_input = "${varname}",
   verbose = .true.,
   l_clean_bitmap = .false.,
   l_increment_intrp = ${flag_increment_intrp},
   interp_opt = 2,
/
EOF

  # exe file for regridding
   export OMP_NUM_THREADS=1
   export pgm="rtma_regrid_esg2rll.exe"
   . prep_step
   rm -f errfile errfile_regrid_howv
   ${APRUN} ${EXECdir}/$pgm  >>$pgmout 2>errfile
   export err=$?; err_chk
   mv errfile errfile_regrid_howv
   print_info_msg "VERBOSE" "Successfully regridding the analysis of wave height (howv) \
                   from ESG grid to RLL grid. "
  # using wgrib2 to convert the netcdf-format howv analysis file to grib2 format (for step prdgen)
  # grib2 template file
   bkpath_howv=${cycle_dir}/process_howv
   if [[ -f ${bkpath_howv}/ww3.guess.grb2 ]] ; then
      print_info_msg "VERBOSE" "found wave height firstguess on RLL grid and 
                      use it as grib2 template."
      ln -sf ${bkpath_howv}/ww3.guess.grb2      ./grb2_tmplate_${varname}.grb2
      # netcdf --> binary (using ncks)
      rm -f ./sfc_data_rll_anl_${varname}_bin.dat ./tmp_${varname}.nc
      # ncks -d X,0,4880 -d Y,0,2960 -C -O -v ${varname} -b ./sfc_data_rll_anl_${varname}_bin.dat -p ./ ./sfc_data_rll_anl_${varname}.nc ./tmp_${varname}.nc
      ncks -C -O -v ${varname} -b ./sfc_data_rll_anl_${varname}_bin.dat -p ./ ./sfc_data_rll_anl_${varname}.nc ./tmp_${varname}.nc

      # convert real8 to real4 in binary file (the binary write-out of ncks is in real-8, wgrib2 only handles real-4)
      cp -p ${HOMEscript}/convert_r8tor4.py   ./
      mv ./sfc_data_rll_anl_${varname}_bin.dat ./sfc_data_rll_anl_${varname}_bin_r8.dat
      python ./convert_r8tor4.py -v -i ./sfc_data_rll_anl_${varname}_bin_r8.dat -o ./sfc_data_rll_anl_${varname}_bin.dat
      # binary --> netcdf (wgrib2)
      export level_info="surface"
      export grib_type="c3"
      export scaling_set=" -set_scaling 0 -4"
      export grib2_fname="sfc_data_rll_anl_${varname}.grb2"
      rm -f ./${grib2_fname}
      wgrib2 ./grb2_tmplate_${varname}.grb2 -import_bin ./sfc_data_rll_anl_${varname}_bin.dat -no_header -set_var ${varname_grb} -set_ftime "anl" -set_date ${adate} -undefine_val -9999.  -set_lev "${level_info}" -set_grib_type $grib_type ${scaling_set} -grib_out ./${grib2_fname}
      export err=$?; err_chk
      print_info_msg "VERBOSE" "Successfully convert netcdf file to grib2 file for ${varname}."
   else
      print_info_msg "VERBOSE" "Could NOT find the grbi2 template file for ${varname}.  \
                      Skipping the conversion from netcdf to grib2."
#     err_exit "Could NOT find grib2 template file for ${varname}. Abort ..."
   fi

fi

#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
post analysis completed successfully!!!

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

