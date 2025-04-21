import json
import sys
import os
import re
from enum import Enum
class State(Enum):
   starting=0
   config=1
   parsing=2

data=[]

if len(sys.argv)!=2:
   print("Usage: %s <logfile to parse>" % (sys.argv[0]))
   exit(-1)

fn = sys.argv[1]
state = State.starting
alg=""

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
               alg = line[:line.index(" ")]
               p = re.compile('\S+\s*\|')
               for i in 0,1,2:
                 x=p.findall(fp.readline().rstrip())
                 tag = x[0][:x[0].index(" ")] # keygen, encaps, decaps
                 ctag = tag+"cycles" # keygencycles, encapscycles, decapscycles
                 iterations = float(x[1][:x[1].index(" ")]) # Iterations
                 total_t = float(x[2][:x[2].index(" ")]) # Total time
                 mean_t = float(x[3][:x[3].index(" ")]) # Mean time in microseconds
                 cycles = float(x[5][:x[5].index(" ")]) # Cycles
                 val = iterations/total_t # Number of iterations per second

               
                 # Add record to dictionary (total time)
                 data.append({"name": alg + " " + tag,
                    "value": round(mean_t,3),
                    "unit": "microseconds"})

                 # Add record to dictionary (total cycles)
                 data.append({"name": alg + " " + tag,
                    "value": int(cycles),
                    "unit": "cycles"})
      else:
           print("Unknown state: %s" % (line))

# Dump data
with open(os.path.splitext(fn)[0]+"_formatted.json", 'w') as outfile:
    json.dump(data, outfile)
