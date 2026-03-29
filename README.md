# code-remote

Skip the repetitive typing when opening VSCode Remote SSH.

Instead of typing:

```bash
code --folder-uri "vscode-remote://ssh-remote+dev.example.com/home/dev/my-project"
```

Just:

```bash
cr dev.example.com my-project
```

Or create a wrapper for hosts you use often:

```bash
cr --create mydev dev.example.com
cr-mydev my-project
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/SiGhaniyGabut/code-remote/main/install.sh | bash
```

Or manually:

```bash
mkdir -p ~/.local/share/code-remote
curl -o ~/.local/share/code-remote/code-remote.sh \
  https://raw.githubusercontent.com/SiGhaniyGabut/code-remote/main/code-remote.sh

# Add to ~/.bashrc
echo 'source ~/.local/share/code-remote/code-remote.sh' >> ~/.bashrc
source ~/.bashrc
```

## Usage

### Basic

```bash
cr [options] <host> [<path>]
```

Opens `vscode-remote://ssh-remote+<host>/<base>/<path>`.

Username is derived from the first segment of the hostname (before the first dot).

```bash
cr example.com                        # user: example → /home/example
cr dev.example.com projects           # user: dev → /home/dev/projects
```

For IP addresses, `--user` is required:

```bash
cr --user admin 192.168.1.100              # /home/admin
cr --user admin 192.168.1.100 projects     # /home/admin/projects
```

Override user:

```bash
cr --user deploy staging.server.local app  # /home/deploy/app
```

Override base path:

```bash
cr --base /var/www dev.example.com             # /var/www
cr --base /var/www dev.example.com mysite      # /var/www/mysite
```

### Wrappers

Create shortcuts for frequently used hosts:

```bash
cr --create mydev dev.example.com
cr-mydev my-project
```

With custom user or base path:

```bash
cr --create web webserver.com --user www --base /var/www
cr-web my-site   # opens /var/www/my-site
```

Manage wrappers:

```bash
cr --list                    # list all
cr --edit mydev new.host.com # update
cr --remove mydev            # delete one
cr --remove-all              # delete all
```

### Help

```bash
cr --help
cr --help create
cr --help edit
```

## Uninstall

```bash
rm -rf ~/.local/share/code-remote
# Then remove this line from ~/.bashrc:
# source ~/.local/share/code-remote/code-remote.sh
```

## Requirements

- Bash
- VSCode with Remote SSH extension
- `code` CLI in PATH

## License

MIT
