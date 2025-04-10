import json
import sys
import os
import re
from enum import Enum

class State(Enum):
   starting=0
   config=1
   parsing=2

data = {}

if len(sys.argv) != 2:
   print("Usage: %s <logfile to parse>" % (sys.argv[0]))
   exit(-1)

fn = sys.argv[1]
state = State.starting
alg = ""

with open(fn) as fp: 
   while True:
      line = fp.readline() 
      if not line: 
            break 
      # Remove newlines
      line = line.rstrip()
      if state == State.starting:
           if line.startswith("Configuration info"):
             state = State.config
             data["config"] = {}
             fp.readline()
      elif state == State.config:
             if line == "\n": # Skip forward
               fp.readline()
               fp.readline()
             if line.startswith("-------"):
                state = State.parsing
             elif line.startswith("Started at"):
                data["config"]["start"] = line[len("Started at "):]
                fp.readline()
             elif ":" in line:
                data["config"][line[:line.index(":")]] = line[line.index(":")+1:].lstrip() 
      elif state == State.parsing:
           if line.startswith("Ended"): # Finish
              break
           else:
               alg = line[:line.index(" ")]
               data[alg] = {}
               p = re.compile('\S+\s*\|')
               for i in 0, 1, 2:
                 x = p.findall(fp.readline().rstrip())
                 tag = x[0][:x[0].index(" ")]
                 ctag = tag + "cycles"
                 iterations = float(x[1][:x[1].index(" ")])
                 t = float(x[2][:x[2].index(" ")])
                 cycles = float(x[5][:x[5].index(" ")])
                 val = iterations / t
                 data[alg][tag] = round(val, 2)
                 data[alg][ctag] = int(cycles)
      else:
           print("Unknown state: %s" % (line))

# Transform data into the required format
output = {
    "name": "Speed KEM Benchmark",
    "unit": "Microseconds",
    "measurements": []
}

for alg, metrics in data.items():
    if alg == "config":
        continue
    for metric, value in metrics.items():
        entry = {
            "name": metric,
            "algorithm": alg,
            "value": value
        }
        output["measurements"].append(entry)

# Dump transformed data
with open(os.path.splitext(fn)[0] + "_formatted.json", 'w') as outfile:
    json.dump(output, outfile, indent=4)
