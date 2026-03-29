# code-remote

Skip the repetitive typing when opening VSCode Remote SSH.

Instead of typing:

```bash
code --folder-uri "vscode-remote://ssh-remote+alice.example.com/home/alice/my-project"
```

Just:

```bash
cr alice.example.com my-project
```

Or create a wrapper for hosts you use often:

```bash
cr --create dev alice.example.com
cr-dev my-project
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/SiGhaniyGabut/cr/main/install.sh | bash
```

Or manually:

```bash
mkdir -p ~/.local/share/code-remote
curl -o ~/.local/share/code-remote/code-remote.sh \
  https://raw.githubusercontent.com/SiGhaniyGabut/cr/main/code-remote.sh

# Add to ~/.bashrc
echo 'source ~/.local/share/code-remote/code-remote.sh' >> ~/.bashrc
source ~/.bashrc
```

## Usage

### Basic

```bash
cr <host> <path>
```

Opens `vscode-remote://ssh-remote+<host>/home/<user>/<path>`.

Username is derived from the host subdomain (`alice.example.com` → `alice`).

Override if needed:

```bash
cr --user admin server.example.com projects
```

### Wrappers

Create shortcuts for frequently used hosts:

```bash
cr --create dev alice.example.com
cr-dev my-project
```

With custom user or base path:

```bash
cr --create web webserver.com --user www --base /var/www
cr-web my-site   # opens /var/www/my-site
```

Manage wrappers:

```bash
cr --list                  # list all
cr --edit dev new.host.com # update
cr --remove dev            # delete one
cr --remove-all            # delete all
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
