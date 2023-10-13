#!/bin/python3

# for exit
import sys
# inquirer for user interaction
import inquirer
# subprocess for ssh execution
import subprocess
# signal for graceful shutdown
import signal
# themes for customization
from inquirer import themes
# Terminal for colorization
from blessed import Terminal
# compile for input parsing
from parse import compile

# List of all supported hosts, either single value "<value>" or aliased "<alias> [<value>]"
host_list = [
    'ubuntu-server [127.0.0.1]',
    'arch-server [127.0.0.1]',
    'some-domain',
]

# Signal handler for graceful termination
def signal_handler(sig, frame):
    sys.exit(0)
signal.signal(signal.SIGINT, signal_handler)

# Ask for text input with default value handling
def ask_text(prompt: str, default: str = None, theme=themes.Default(), extract=None):
    message = f"{prompt} [{default}]" if default else f"{prompt}"
    questions = [inquirer.Text('input', message=message)]
    answer = inquirer.prompt(questions, theme=theme)
    if answer and answer['input']:
        value = extract(answer['input']) if extract else answer['input']
        info(f"Received value '{value}'.")
        return value
    elif answer:
        info(f"Using default '{default}'.")
        return default
    else:
        sys.exit(1)

# Ask for list choice
def ask_list(prompt: str, choices: [str], theme=themes.Default(), extract=None):
    questions = [inquirer.List('input', message=prompt, choices=choices)]
    answer = inquirer.prompt(questions, theme=theme)
    if answer and answer['input']:
        value = extract(answer['input']) if extract else answer['input']
        info(f"Received value '{value}'.")
        return value
    elif answer: 
        return None
    else:
        sys.exit(1)

# Execute command
def execute(cmd=[str]):
    cmd_line = " ".join(cmd)
    print(f"[{term.orangered}!{term.normal}] Execute '{cmd_line}'")
    subprocess.run(cmd)

# Print info
def info(msg: str):
    print(f"[{term.aqua}+{term.normal}] {msg}")

# Customize theme of inquirer
term = Terminal()
theme = themes.Default()
theme.List.selection_color = term.goldenrod1

# Extract host IP if aliased
def extract_value_if_aliased(input_str: str):
    parser = compile("{} [{}]")
    parsed = parser.parse(input_str)
    return parsed[1] if parsed else input_str

# Get user input
user = ask_text("What's your username?", default="dloewe", theme=theme)
port = ask_text("What port to use?", default=22, theme=theme)
host = ask_list("What host to connect to?", choices=host_list + ['Not listed'], theme=theme, extract=extract_value_if_aliased)
if not host or host == "Not listed":
    host = ask_text("Specify name of host", theme=theme)

# Run SSH
execute(['ssh', '-p', f"{port}", f"{user}@{host}"])

# Terminating
info("Terminating.")
