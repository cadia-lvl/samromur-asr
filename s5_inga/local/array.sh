#!/bin/bash

error_array=(
  [3]="Incorrect number of inputs"
  [4]="Incorrect audio file name format, should be rad<year><month><date>T<hr><min><sec>"
  [5]="The input is not an audio file"
  [6]="Empty audio file"
  [7]="Error finding the best path through the decoding lattice"
  [8]="Error while rewriting text using FSTs based on Thrax grammar"
  [9]="Error while applying the punctuation model"
  [10]="Error while applying the paragraph model"
  [11]="Failed to activate virtual environment"
  [12]="Could not calculate prediction errors (error_calculator.py)"
  [13]="Error while applying regular expressions"
  [14]="Bash command error"
)
