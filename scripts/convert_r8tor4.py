#!/bin/env python

import os, sys, shutil

import numpy as np

import argparse
#====================================================================================================#
# main program driver
if __name__ == '__main__':
  verbose = True

  print('Starting...')

  #=====================================================================================#
  # Reading the input (float64 binary) file name and output (float32 binary) file name  #
  #     from the comand line options/arguments                                          #
  #=====================================================================================#
  # Creating a parser, an ArgumentParser object
  parser = argparse.ArgumentParser(
                      prog='bin_r8tor4',
                      description='Converting float64 binary data file to float32.',
                      epilog='-- If found an issue, email Gang.Zhao@noaa.gov .')

  # Adding arguments
  parser.add_argument('-i', '--input', type=str, action='store',
                      dest='input_filename',
                      help='input file name (binary with type float64)',
                      required=True)
  parser.add_argument('-o', '--output', type=str, action='store',
                      dest='output_filename',
                      help='input file name (binary with type float32)',
                      default='outputf32_bin.dat',
                      required=False)
  parser.add_argument('-r', '--reverse', action='store_true', 
                      help='cconvert from float32 to float64 reversely')
  parser.add_argument('-v', '--verbose', action='store_true', 
                      help='increase verbosity')

  # Parsing the command-line arguments
  args = parser.parse_args()

  # Access and print the arguments
  filename_input  = args.input_filename
  filename_output = args.output_filename

  if args.reverse :
     dtype_bin_in  = np.dtype('f4')  # data type in input binary file
     dtype_bin_out = np.dtype('f8')  # data type in output binary file
  else:
     dtype_bin_in  = np.dtype('f8')  # data type in input binary file
     dtype_bin_out = np.dtype('f4')  # data type in output binary file

  #=====================================================================================#
  # Reading data from the input (float64 binary) file                                   #
  #=====================================================================================#
  print('    ----> reading original data from binary file : ', filename_input)
  with open(filename_input, mode='rb') as f_in_h:
#    binContent = f_in_h.read()
#  binData = np.frombuffer(binContent, dtype=dtype_bin_in)
    binData = np.fromfile(f_in_h, dtype=dtype_bin_in)
    if args.verbose :
       print('')
       print('  the size of data read from file is ', binData.size, '  <-- check if it is the number as expected.')
       print('')
    f_in_h.close()
  
  #=====================================================================================#
  # Writing data to the output (float32 binary) file                                   #
  #=====================================================================================#
  print('    ----> writing data to binary file : ', filename_output)
  with open(filename_output, mode='wb') as f_out_h:
    np.array(binData, dtype=dtype_bin_out).tofile(f_out_h)
    f_out_h.close()
