import json
import sys
import os
import re
from enum import Enum

class State(Enum):
    starting = 0
    config = 1
    parsing = 2

results = []

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
                fp.readline()
        elif state == State.config:
            if line == "\n":  # Skip forward
                fp.readline()
                fp.readline()
            if line.startswith("-------"):
                state = State.parsing
            elif line.startswith("Started at"):
                fp.readline()
            elif ":" in line:
                pass
        elif state == State.parsing:
            if line.startswith("Ended"):  # Finish
                break
            else:
                alg = line[:line.index(" ")]
                p = re.compile(r'\S+\s*\|')
                for i in 0, 1, 2:
                    x = p.findall(fp.readline().rstrip())
                    tag = x[0][:x[0].index(" ")]
                    ctag = tag + "cycles"
                    iterations = float(x[1][:x[1].index(" ")])
                    t = float(x[2][:x[2].index(" ")])
                    cycles = float(x[5][:x[5].index(" ")])
                    val = iterations / t
                    # Append benchmark results based on tag
                    if "cycles" in ctag.lower():
                        results.append({
                            "name": f"{alg} - {ctag}",
                            "value": int(cycles),
                            "unit": "Cycles"
                        })
                    else:
                        results.append({
                            "name": f"{alg} - {tag}",
                            "value": round(val, 2),
                            "unit": "Microseconds"
                        })
        else:
            print("Unknown state: %s" % (line))

# Dump results as a flat array
output_file = os.path.splitext(fn)[0] + "_formatted.json"
with open(output_file, 'w') as outfile:
    json.dump(results, outfile, indent=4)