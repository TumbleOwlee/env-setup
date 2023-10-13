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

# Customize theme of inquirer
term = Terminal()
theme = themes.Default()
theme.List.selection_color = term.goldenrod1

# Parser for retrieval of ip (if applicable)
parser = compile("{} [{}]")

# Default values
default_user = "dloewe"
default_port = 22

# User interaction
questions = [
    inquirer.Text('user', message=f"What's your username? [{default_user}]"),
    inquirer.Text('port', message=f"What port to use? [{default_port}]"),
    inquirer.List('hosts', message="What host to connect to?", choices=host_list),
]
answers = inquirer.prompt(questions, theme=theme)

# If host is chosen
if answers and 'hosts' in answers:
    # Extract input
    user = answers['user'] if 'user' in answers and not answers['user'] == "" else default_user
    port = answers['port'] if 'port' in answers and not answers['port'] == "" else default_port
    host = answers['hosts']
    
    # Check if host has IP besides hostname
    parsed = parser.parse(host)
    if parsed:
        host = parsed[1]
    
    # Run SSH
    print(f"[{term.orangered}!{term.normal}] Execute 'ssh -p {port} {user}@{host}'")
    subprocess.run(['ssh', '-p', f"{port}", f"{user}@{host}"])
