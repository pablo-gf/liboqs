import json
import sys
import os
import re
from enum import Enum
import time

class State(Enum):
    starting = 0
    config = 1
    parsing = 2

# Metadata for the output JSON
repo_url = "https://github.com/pablo-gf/liboqs/tree/bench"
commit_info = {
    "author": {
        "email": "matthias@kannwischer.eu",
        "name": "Matthias J. Kannwischer",
        "username": "mkannwischer"
    },
    "committer": {
        "email": "noreply@github.com",
        "name": "GitHub",
        "username": "web-flow"
    },
    "distinct": True,
    "id": "de9203e2161ca48bc4daf7c30ea8e80ae77557d7",
    "message": "Add github benchmark action (#78)",
    "timestamp": "2024-06-26T13:46:54+01:00",
    "tree_id": "a0be78ac5569604219677d305ab65d0daa0b8192",
    "url": "https://github.com/pq-code-package/mlkem-c-aarch64/commit/de9203e2161ca48bc4daf7c30ea8e80ae77557d7"
}

if len(sys.argv) != 2:
    print("Usage: %s <logfile to parse>" % (sys.argv[0]))
    exit(-1)

fn = sys.argv[1]
state = State.starting
alg = ""

# Initialize the output structure
output_data = {
    "lastUpdate": int(time.time() * 1000),  # Current timestamp in milliseconds
    "repoUrl": repo_url,
    "entries": {
        "Arm Cortex-A72 (Raspberry Pi 4) benchmarks": [
            {
                "commit": commit_info,
                "date": int(time.time() * 1000),  # Current timestamp in milliseconds
                "tool": "customSmallerIsBetter",
                "benches": []
            }
        ]
    }
}

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
                    # Append benchmark results
                    output_data["entries"]["Arm Cortex-A72 (Raspberry Pi 4) benchmarks"][0]["benches"].append({
                        "name": f"{alg} {tag}",
                        "value": round(val, 2),
                        "unit": "Microseconds"
                    })
                    output_data["entries"]["Arm Cortex-A72 (Raspberry Pi 4) benchmarks"][0]["benches"].append({
                        "name": f"{alg} {ctag}",
                        "value": int(cycles),
                        "unit": "Cycles"
                    })
        else:
            print("Unknown state: %s" % (line))

# Dump the output data
output_file = os.path.splitext(fn)[0] + "_formatted.json"
with open(output_file, 'w') as outfile:
    json.dump(output_data, outfile, indent=4)