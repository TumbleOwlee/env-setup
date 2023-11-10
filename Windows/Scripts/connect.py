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
from parse import parse

# Customize theme of inquirer
term = Terminal()
theme = themes.Default()
theme.List.selection_color = term.yellow

# Host class holding all info
class Host:
    def __init__(self, url = None, user = None, port = None, alias = None):
        self.url = url
        self.user = user
        self.port = port
        self.alias = alias

    def _colorize(self):
        user = f"{term.blue}{self.user}{term.yellow}@{term.normal}" if self.user else ""
        url = f"{term.yellow}{self.url}{term.normal}" if self.url else ""
        port = f"{term.green}:{self.port}{term.normal}" if self.port else ""
        if self.url:
            return f"{self.alias} {term.normal}[{user}{url}{port}{term.normal}]"
        else:
            return self.alias

    def __str__(self):
        return self._colorize()

# List of all configured hosts
host_list = [
    Host("url", "user", "port", "alias"),
    Host(None, None, None, "Other..")
]

# Print info
def info(msg: str):
    print(f"[{term.aqua}+{term.normal}] {msg}")

# Signal handler for graceful termination
def signal_handler(sig, frame):
    info(f"Received signal {sig}. Terminating.")
    sys.exit(0)
signal.signal(signal.SIGINT, signal_handler)

# Ask for text input with default value handling
def ask_text(prompt: str, default: str = None, theme=themes.Default()):
    message = f"{prompt} [{default}]" if default else f"{prompt}"
    questions = [inquirer.Text('input', message=message)]
    answer = inquirer.prompt(questions, theme=theme)
    if answer and answer['input']:
        value = answer['input']
        info(f"Received value '{value}'.")
        return value
    elif answer:
        info(f"Using default '{default}'.")
        return default
    else:
        sys.exit(1)

# Ask for list choice
def ask_list(prompt: str, choices: [str], theme=themes.Default()):
    questions = [inquirer.List('input', message=prompt, choices=choices)]
    answer = inquirer.prompt(questions, theme=theme)
    if answer and answer['input']:
        value = answer['input']
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

# Get user input
host = ask_list("What host to connect to?", choices=host_list, theme=theme)
if host.url == None:
    host.url = ask_text("Specify name of host", theme=theme)
if host.user == None:
    host.user = ask_text("What's your username?", default=host.user or os.environ.get('USER', os.environ.get('USERNAME')), theme=theme)
if host.port == None:
    host.port = ask_text("What port to use?", default=host.port or 22, theme=theme)

# Run SSH
execute(['ssh', '-p', f"{host.port}", f"{host.user}@{host.url}"])

# Terminating
info("Terminating.")
