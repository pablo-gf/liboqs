import json
import sys
import os
import re
import argparse
from enum import Enum

class State(Enum):
   starting=0
   config=1
   parsing=2

data=[]

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Parse speed_kem output and extract cycles.")
parser.add_argument("logfile", help="Log file to parse")
parser.add_argument("--algorithm", help="Algorithm name (e.g., BIKE-L1)", required=True)
args = parser.parse_args()

fn = args.logfile
alg = args.algorithm
state = State.starting

with open(fn) as fp: 
   while True:
      line = fp.readline() 
      if not line: 
            break 
      # Remove newlines
      line = line.rstrip()
      if state==State.starting:
           if line.startswith("Configuration info"):
             state=State.config
             fp.readline()
      elif state==State.config:
             if line=="\n": # Skip forward
               fp.readline()
               fp.readline()
             if line.startswith("-------"):
                state=State.parsing
             elif line.startswith("Started at"):
                fp.readline()
      elif state==State.parsing:
           if line.startswith("Ended"): # Finish
              break
           else:
               p = re.compile(r'\|\s*([^|]+?)\s*(?=\|)')
               for i in range(3):  # keygen, encaps, decaps
                   x = p.findall(fp.readline().rstrip())
                   tag = x[0].strip()  # keygen, encaps, decaps
                   ctag = tag + "cycles"  # keygencycles, encapscycles, decapscycles
                   cycles = int(x[5].strip())  # Cycles

                   # Add record to dictionary (total cycles)
                   data.append({"name": alg + " " + tag, "value": cycles, "unit": "cycles"})
      else:
           print("Unknown state: %s" % (line))

# Dump data
output_file = f"{alg}_formatted.json"
with open(output_file, 'w') as outfile:
    json.dump(data, outfile)
